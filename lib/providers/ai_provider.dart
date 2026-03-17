import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database.dart' as db;
import '../models/chat_session.dart';
import '../models/note.dart';
import '../models/vault_entry.dart';
import '../services/ai_service.dart';
import '../services/embedding_service.dart';
import 'embedding_provider.dart';
import 'notes_provider.dart';
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

  const AiChatState({
    this.messages = const [],
    this.isProcessing = false,
    this.error,
    this.loadedSessionId,
    this.loadedSessionTitle,
  });

  AiChatState copyWith({
    List<ChatMessage>? messages,
    bool? isProcessing,
    String? Function()? error,
    String? Function()? loadedSessionId,
    String? Function()? loadedSessionTitle,
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
    );
  }
}

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

      final entriesAsync = _ref.read(vaultEntriesProvider);
      final entries = entriesAsync.whenOrNull<List<VaultEntry>>(
            data: (data) => data,
          ) ??
          [];

      final notesAsync = _ref.read(notesProvider);
      final notesList = notesAsync.whenOrNull<List<Note>>(
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

              final entryIds = topK
                  .where((s) => s.sourceType == 'vault_entry')
                  .map((s) => s.sourceId)
                  .toSet();
              final noteIds = topK
                  .where((s) => s.sourceType == 'note')
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

      final response = await aiService.chat(
        query,
        history,
        entries,
        notesList,
        ragEntries: ragEntries,
        ragNotes: ragNotes,
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
        aiOnline: response.aiOnline,
        isVaultResult: response.isVaultResult,
        ragUsed: response.ragUsed,
        ragSources: response.ragSources,
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMessage],
        isProcessing: false,
      );
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
