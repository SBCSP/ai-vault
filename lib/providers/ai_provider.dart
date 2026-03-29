import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database.dart' as db;
import '../models/chat_session.dart';
import '../models/idea.dart';
import '../models/note.dart';
import '../models/vault_entry.dart';
import '../services/ai_service.dart';
import '../services/embedding_service.dart';
import '../services/mcp_service.dart';
import 'audit_provider.dart';
import 'embedding_provider.dart';
import 'ideas_provider.dart';
import 'mcp_provider.dart';
import 'notes_provider.dart';
import 'secrets_lock_provider.dart';
import 'vault_provider.dart';

final aiServiceProvider =
    StateNotifierProvider<AiServiceNotifier, AiService>((ref) {
  return AiServiceNotifier();
});

class AiServiceNotifier extends StateNotifier<AiService> {
  AiServiceNotifier() : super(AiService()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('ai_server_url');
    final model = prefs.getString('ai_model');
    if (url != null) state.updateServerUrl(url);
    if (model != null) state.updateModel(model);
  }

  Future<void> updateServerUrl(String url) async {
    state.updateServerUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_server_url', url);
  }

  Future<void> updateModel(String model) async {
    state.updateModel(model);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_model', model);
  }
}

// --- AI Chat Provider ---
// Maintains conversation history in memory for multi-turn chat.

final aiChatProvider =
    StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  return AiChatNotifier(ref);
});

class AiChatState {
  final List<ChatMessage> messages;
  final bool isProcessing;
  final String? error;
  final String? loadedSessionId;
  final String? loadedSessionTitle;
  final String? processingStatus;

  const AiChatState({
    this.messages = const [],
    this.isProcessing = false,
    this.error,
    this.loadedSessionId,
    this.loadedSessionTitle,
    this.processingStatus,
  });

  AiChatState copyWith({
    List<ChatMessage>? messages,
    bool? isProcessing,
    String? Function()? error,
    String? Function()? loadedSessionId,
    String? Function()? loadedSessionTitle,
    String? Function()? processingStatus,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error != null ? error() : this.error,
      loadedSessionId: loadedSessionId != null
          ? loadedSessionId()
          : this.loadedSessionId,
      loadedSessionTitle: loadedSessionTitle != null
          ? loadedSessionTitle()
          : this.loadedSessionTitle,
      processingStatus: processingStatus != null
          ? processingStatus()
          : this.processingStatus,
    );
  }
}

/// Provider to check if the current Ollama model supports tool calling.
final modelSupportsToolsProvider = FutureProvider<bool>((ref) async {
  final aiService = ref.watch(aiServiceProvider);
  return aiService.supportsTools();
});

class AiChatNotifier extends StateNotifier<AiChatState> {
  final Ref _ref;

  AiChatNotifier(this._ref) : super(const AiChatState());

  Future<void> sendMessage(String query) async {
    if (query.trim().isEmpty) return;

    // Add user message
    final userMessage = ChatMessage(
      text: query,
      isUser: true,
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isProcessing: true,
      error: () => null,
    );

    try {
      final aiService = _ref.read(aiServiceProvider);

      final secretsLocked = _ref.read(secretsLockProvider);

      final List<VaultEntry> entries;
      if (secretsLocked) {
        entries = [];
      } else {
        final entriesAsync = _ref.read(vaultEntriesProvider);
        entries = entriesAsync.whenOrNull<List<VaultEntry>>(
              data: (data) => data,
            ) ??
            [];
      }

      final notesAsync = _ref.read(notesProvider);
      final notesList = notesAsync.whenOrNull<List<Note>>(
            data: (data) => data,
          ) ??
          [];

      final ideasAsync = _ref.read(ideasProvider);
      final ideaList = ideasAsync.whenOrNull<List<Idea>>(
            data: (data) => data,
          ) ??
          [];

      // Pass conversation history (exclude the message we just added —
      // the chat() method receives the query separately)
      final history = state.messages
          .where((m) => m != userMessage)
          .toList();

      // --- RAG pipeline: embed query and find top-K relevant items ---
      List<VaultEntry>? ragEntries;
      List<Note>? ragNotes;
      List<Idea>? ragIdeas;
      List<db.DocumentChunk>? ragChunks;
      List<String> ragDocumentTitles = [];
      List<ChatSession>? ragChatSessions;
      bool ragUsed = false;

      try {
        final embeddingService = _ref.read(embeddingServiceProvider);
        final database = _ref.read(databaseProvider);

        final queryVector =
            await embeddingService.generateEmbedding(query);

        if (queryVector != null) {
          final allEmbeddings = await database.getAllEmbeddings();

          if (allEmbeddings.isNotEmpty) {
            // Score each embedding against the query
            final scored = <({String sourceId, String sourceType, double score})>[];
            for (final emb in allEmbeddings) {
              final vector = (jsonDecode(emb.embedding) as List<dynamic>)
                  .map((e) => (e as num).toDouble())
                  .toList();
              final score =
                  EmbeddingService.cosineSimilarity(queryVector, vector);
              scored.add((
                sourceId: emb.sourceId,
                sourceType: emb.sourceType,
                score: score,
              ));
            }

            // Sort by score descending, filter by minimum threshold, take top 10
            scored.sort((a, b) => b.score.compareTo(a.score));
            final topK = scored
                .where((s) => s.score >= 0.3)
                .take(10)
                .toList();

            if (topK.isNotEmpty) {
              ragUsed = true;

              final entryIds = secretsLocked
                  ? <String>{}
                  : topK
                      .where((s) => s.sourceType == 'vault_entry')
                      .map((s) => s.sourceId)
                      .toSet();
              final noteIds = topK
                  .where((s) => s.sourceType == 'note')
                  .map((s) => s.sourceId)
                  .toSet();
              final ideaIds = topK
                  .where((s) => s.sourceType == 'idea')
                  .map((s) => s.sourceId)
                  .toSet();
              final chunkIds = topK
                  .where((s) => s.sourceType == 'document_chunk')
                  .map((s) => s.sourceId)
                  .toSet();
              final chatSessionIds = topK
                  .where((s) => s.sourceType == 'chat_session')
                  .map((s) => s.sourceId)
                  .toSet();

              // Always set RAG-filtered lists (even if empty) so
              // we don't fall back to sending the entire vault
              ragEntries =
                  entries.where((e) => entryIds.contains(e.id)).toList();
              ragNotes =
                  notesList.where((n) => noteIds.contains(n.id)).toList();
              ragIdeas =
                  ideaList.where((i) => ideaIds.contains(i.id)).toList();

              if (chunkIds.isNotEmpty) {
                ragChunks =
                    await database.getChunksByIds(chunkIds.toList());
                // Fetch document titles for matched chunks
                final docIds = ragChunks
                    .map((c) => c.documentId)
                    .toSet();
                for (final docId in docIds) {
                  final doc = await database.getDocumentById(docId);
                  if (doc != null) {
                    ragDocumentTitles.add(doc.title);
                  }
                }
              }

              if (chatSessionIds.isNotEmpty) {
                ragChatSessions = [];
                for (final sessionId in chatSessionIds) {
                  final session =
                      await database.getChatSessionById(sessionId);
                  if (session != null) {
                    ragChatSessions.add(ChatSession(
                      id: session.id,
                      title: session.title,
                      messages: ChatSession.parseMessages(session.messages),
                      isIndexed: session.isIndexed,
                      createdAt: session.createdAt,
                      updatedAt: session.updatedAt,
                    ));
                  }
                }
              }
            }
          }
        }
      } catch (_) {
        // RAG failed — fall back to full context silently
      }

      // --- MCP tool-calling path ---
      final mcpState = _ref.read(mcpProvider);
      final mcpTools = mcpState.availableTools;

      // If MCP servers are connected with tools, always try the tool-calling path.
      // The model will simply not emit tool_calls if it doesn't support them,
      // and we'll fall through to treating the response as plain text.
      final bool useMcpTools = mcpTools.isNotEmpty;

      if (useMcpTools) {
        // Tool-calling path: build messages, send with tools, loop
        final mcpNotifier = _ref.read(mcpProvider.notifier);
        final mcpService = mcpNotifier.mcpService;
        final auditLogger = _ref.read(auditLoggerProvider);

        // Build vault context
        final contextEntries = (ragEntries != null && ragEntries.isNotEmpty)
            ? ragEntries
            : entries;
        final contextNotes = (ragNotes != null && ragNotes.isNotEmpty)
            ? ragNotes
            : notesList;
        final contextIdeas = (ragIdeas != null && ragIdeas.isNotEmpty)
            ? ragIdeas
            : ideaList;
        final vaultContext = aiService.buildVaultContext(
          contextEntries,
          contextNotes,
          ideas: contextIdeas,
          documentChunks: ragChunks,
          documentTitles: ragDocumentTitles,
          chatSessions: ragChatSessions,
        );

        final ollamaTools = mcpService.getOllamaToolsJson();

        // Build a human-readable tool summary for the system prompt
        final toolSummaryBuf = StringBuffer();
        toolSummaryBuf.writeln('\n\nAVAILABLE TOOLS:');
        for (final tool in mcpTools) {
          toolSummaryBuf.writeln('- ${tool.name}: ${tool.description}');
        }

        final messages = <Map<String, dynamic>>[
          {
            'role': 'system',
            'content': '${AiService.systemPrompt}${AiService.mcpToolsPromptSuffix}$toolSummaryBuf\n\n$vaultContext',
          },
          ...history.map((m) => <String, dynamic>{
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              }),
          {'role': 'user', 'content': query},
        ];

        const maxRounds = 10;
        var round = 0;
        String finalText = '';
        final allToolCalls = <ToolCallInfo>[];

        while (round < maxRounds) {
          round++;

          if (!mounted) return;
          state = state.copyWith(
            processingStatus: () => round == 1
                ? 'Thinking with tools...'
                : 'Processing tool results (round $round)...',
          );

          final toolResponse = await aiService.chatWithTools(
            messages,
            tools: ollamaTools,
          );

          if (toolResponse.isError) {
            finalText = toolResponse.error ?? 'Unknown error';
            break;
          }

          if (toolResponse.isToolCall && toolResponse.toolCalls != null) {
            // Add assistant message with tool_calls to conversation
            messages.add({
              'role': 'assistant',
              'content': '',
              'tool_calls': toolResponse.toolCalls!
                  .map((tc) => {
                        'function': {
                          'name': tc.name,
                          'arguments': tc.arguments,
                        },
                      })
                  .toList(),
            });

            // Execute each tool call via MCP
            for (final tc in toolResponse.toolCalls!) {
              if (!mounted) return;
              state = state.copyWith(
                processingStatus: () => 'Calling ${tc.name}...',
              );

              final serverId = mcpService.toolToServerMap[tc.name];
              if (serverId == null) {
                messages.add({
                  'role': 'tool',
                  'content': 'Error: tool "${tc.name}" not found on any connected MCP server',
                });
                allToolCalls.add(ToolCallInfo(
                  toolName: tc.name,
                  serverName: 'unknown',
                  arguments: tc.arguments,
                  error: 'Tool not found',
                ));
                continue;
              }

              final serverName = mcpTools
                  .where((t) => t.name == tc.name)
                  .map((t) => t.serverName)
                  .firstOrNull ?? serverId;

              final stopwatch = Stopwatch()..start();
              try {
                final result = await mcpService.callTool(
                  serverId,
                  tc.name,
                  tc.arguments,
                );
                stopwatch.stop();

                messages.add({
                  'role': 'tool',
                  'content': result,
                });
                allToolCalls.add(ToolCallInfo(
                  toolName: tc.name,
                  serverName: serverName,
                  arguments: tc.arguments,
                  result: result,
                  duration: stopwatch.elapsed,
                ));

                auditLogger.log(
                  action: AuditAction.mcpToolCalled,
                  targetType: 'mcp_tool',
                  targetName: tc.name,
                  details: 'Server: $serverName, Duration: ${stopwatch.elapsedMilliseconds}ms',
                );
              } catch (e) {
                stopwatch.stop();
                messages.add({
                  'role': 'tool',
                  'content': 'Error: ${e.toString()}',
                });
                allToolCalls.add(ToolCallInfo(
                  toolName: tc.name,
                  serverName: serverName,
                  arguments: tc.arguments,
                  error: e.toString(),
                  duration: stopwatch.elapsed,
                ));

                auditLogger.log(
                  action: AuditAction.mcpToolFailed,
                  targetType: 'mcp_tool',
                  targetName: tc.name,
                  details: 'Server: $serverName, Error: ${e.toString()}',
                );
              }
            }
          } else {
            // Final text response
            finalText = toolResponse.text ?? '';
            break;
          }
        }

        if (!mounted) return;

        // Extract referenced items from final text
        final referenced = aiService.extractReferencedItems(
          finalText, entries, notesList, ideaList,
        );
        final cleanText = aiService.cleanResponse(finalText);

        final assistantMessage = ChatMessage(
          text: cleanText,
          isUser: false,
          matchedEntries: referenced.entries,
          matchedNotes: referenced.notes,
          matchedIdeas: referenced.ideas,
          aiOnline: true,
          isVaultResult: referenced.entries.isNotEmpty ||
              referenced.notes.isNotEmpty ||
              referenced.ideas.isNotEmpty,
          ragUsed: ragUsed,
          ragSources: aiService.buildRagSourceSummary(
            ragEntries, ragNotes, ragIdeas, ragChunks,
            ragDocumentTitles, ragChatSessions,
          ),
          toolCalls: allToolCalls,
          mcpUsed: true,
        );

        state = state.copyWith(
          messages: [...state.messages, assistantMessage],
          isProcessing: false,
          processingStatus: () => null,
        );
      } else {
        // Standard path — no MCP tools or model doesn't support them
        final response = await aiService.chat(
          query,
          history,
          entries,
          notesList,
          ideaList,
          ragEntries: ragEntries,
          ragNotes: ragNotes,
          ragIdeas: ragIdeas,
          ragChunks: ragChunks,
          ragDocumentTitles: ragDocumentTitles,
          ragChatSessions: ragChatSessions,
          ragUsed: ragUsed,
        );

        if (!mounted) return;

        final assistantMessage = ChatMessage(
          text: response.text,
          isUser: false,
          matchedEntries: response.matchedEntries,
          matchedNotes: response.matchedNotes,
          matchedIdeas: response.matchedIdeas,
          aiOnline: response.aiOnline,
          isVaultResult: response.isVaultResult,
          ragUsed: response.ragUsed,
          ragSources: response.ragSources,
        );

        state = state.copyWith(
          messages: [...state.messages, assistantMessage],
          isProcessing: false,
          processingStatus: () => null,
        );
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isProcessing: false,
        error: () => e.toString(),
      );
    }
  }

  void newChat() {
    state = const AiChatState();
  }

  /// Load a saved chat session into the current chat state.
  void loadSession(ChatSession session) {
    final messages = session.messages.map((m) => ChatMessage(
          text: m.text,
          isUser: m.isUser,
        )).toList();

    state = AiChatState(
      messages: messages,
      loadedSessionId: session.id,
      loadedSessionTitle: session.title,
    );
  }

  /// Mark that the current session has been saved.
  void markSaved(String sessionId, String title) {
    state = state.copyWith(
      loadedSessionId: () => sessionId,
      loadedSessionTitle: () => title,
    );
  }
}

// --- Model Download Provider ---
// Persists download state across navigation so downloads continue in background.

final modelDownloadProvider =
    StateNotifierProvider<ModelDownloadNotifier, ModelDownloadState>((ref) {
  return ModelDownloadNotifier(ref);
});

class ModelDownloadState {
  final bool isDownloading;
  final String? modelName;
  final String status;
  final double? progress; // 0.0 - 1.0
  final String? error;
  final bool completed;

  const ModelDownloadState({
    this.isDownloading = false,
    this.modelName,
    this.status = '',
    this.progress,
    this.error,
    this.completed = false,
  });

  ModelDownloadState copyWith({
    bool? isDownloading,
    String? modelName,
    String? status,
    double? Function()? progress,
    String? Function()? error,
    bool? completed,
  }) {
    return ModelDownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      modelName: modelName ?? this.modelName,
      status: status ?? this.status,
      progress: progress != null ? progress() : this.progress,
      error: error != null ? error() : this.error,
      completed: completed ?? this.completed,
    );
  }
}

class ModelDownloadNotifier extends StateNotifier<ModelDownloadState> {
  final Ref _ref;

  ModelDownloadNotifier(this._ref) : super(const ModelDownloadState());

  Future<void> downloadModel(String modelName) async {
    if (state.isDownloading) return; // Prevent concurrent downloads

    state = ModelDownloadState(
      isDownloading: true,
      modelName: modelName,
      status: 'Starting download...',
    );

    final aiService = _ref.read(aiServiceProvider);

    try {
      await for (final update in aiService.pullModel(modelName)) {
        if (!mounted) return;

        final status = update['status'] as String? ?? '';

        if (update.containsKey('error')) {
          state = ModelDownloadState(
            isDownloading: false,
            modelName: modelName,
            status: '',
            error: update['error'] as String?,
          );
          return;
        }

        if (update.containsKey('completed') && update.containsKey('total')) {
          final completed = update['completed'] as int;
          final total = update['total'] as int;
          if (total > 0) {
            final pct = (completed / total * 100).toStringAsFixed(0);
            final mb = (completed / 1024 / 1024).toStringAsFixed(0);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(0);
            state = ModelDownloadState(
              isDownloading: true,
              modelName: modelName,
              status: '$status — ${mb}MB / ${totalMb}MB ($pct%)',
              progress: completed / total,
            );
          }
        } else {
          state = ModelDownloadState(
            isDownloading: true,
            modelName: modelName,
            status: status,
          );
        }
      }

      if (mounted) {
        state = ModelDownloadState(
          isDownloading: false,
          modelName: modelName,
          status: 'Done! $modelName is ready to use.',
          completed: true,
        );
      }
    } catch (e) {
      if (mounted) {
        state = ModelDownloadState(
          isDownloading: false,
          modelName: modelName,
          error: e.toString(),
        );
      }
    }
  }

  void clearCompleted() {
    if (!state.isDownloading) {
      state = const ModelDownloadState();
    }
  }
}
