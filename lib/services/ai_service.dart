import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/database.dart' as db;
import '../models/chat_session.dart';
import '../models/idea.dart';
import '../models/note.dart';
import '../models/vault_entry.dart';
import 'mcp_service.dart';

/// A request from the LLM to call a tool.
class ToolCallRequest {
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCallRequest({required this.name, required this.arguments});
}

/// Response from chatWithTools — either final text or tool call requests.
class AiToolResponse {
  final String? text;
  final List<ToolCallRequest>? toolCalls;
  final String? error;

  bool get isToolCall => toolCalls != null && toolCalls!.isNotEmpty;
  bool get isError => error != null;

  const AiToolResponse._({this.text, this.toolCalls, this.error});

  factory AiToolResponse.text(String text) => AiToolResponse._(text: text);
  factory AiToolResponse.toolCalls(List<ToolCallRequest> calls) =>
      AiToolResponse._(toolCalls: calls);
  factory AiToolResponse.withError(String error) => AiToolResponse._(error: error);
}

class AiService {
  String _serverUrl;
  String _model;

  AiService({
    String serverUrl = 'http://localhost:11434',
    String model = 'gemma3:1b',
  })  : _serverUrl = serverUrl,
        _model = model;

  String get serverUrl => _serverUrl;
  String get model => _model;

  void updateServerUrl(String url) {
    _serverUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  void updateModel(String model) {
    _model = model;
  }

  /// Simple connection test - checks both Ollama AND model availability.
  Future<bool> testConnection() async {
    final status = await checkStatus();
    return status.status == OllamaConnectionStatus.ready;
  }

  /// Full status check: is Ollama running? Is the configured model available?
  Future<OllamaStatus> checkStatus() async {
    List<String> availableModels;
    try {
      final response = await http
          .get(Uri.parse('$_serverUrl/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return const OllamaStatus(
          status: OllamaConnectionStatus.ollamaNotRunning,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final models = json['models'] as List<dynamic>? ?? [];
      availableModels = models
          .map((m) => (m as Map<String, dynamic>)['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (_) {
      return const OllamaStatus(
        status: OllamaConnectionStatus.ollamaNotRunning,
      );
    }

    final modelLower = _model.toLowerCase();
    final hasModel = availableModels.any((m) {
      final mLower = m.toLowerCase();
      return mLower == modelLower ||
          mLower.startsWith(modelLower) ||
          modelLower == mLower.split(':').first;
    });

    if (!hasModel) {
      return OllamaStatus(
        status: OllamaConnectionStatus.modelNotFound,
        availableModels: availableModels,
      );
    }

    return OllamaStatus(
      status: OllamaConnectionStatus.ready,
      availableModels: availableModels,
    );
  }

  /// Pull (download) a model from Ollama. Returns a stream of progress updates.
  Stream<Map<String, dynamic>> pullModel(String modelName) async* {
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_serverUrl/api/pull'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'name': modelName, 'stream': true});

      final response = await http.Client().send(request);

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (line.trim().isEmpty) continue;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            yield json;
          } catch (_) {
            // Skip malformed lines
          }
        }
      }
    } catch (e) {
      yield {'status': 'error', 'error': e.toString()};
    }
  }

  static const systemPrompt = 'You are a personal vault assistant. '
      'The user has a collection of saved records, notes, and documents shown below under "USER RECORDS". '
      'Your ONLY source of truth is the data provided in that section.\n\n'
      'CRITICAL RULES:\n'
      '1. NEVER invent, fabricate, or guess records. ONLY reference items explicitly listed in the USER RECORDS section below.\n'
      '2. If the user asks about something NOT in the provided records, clearly say "I don\'t see that in your vault" — do NOT make up data.\n'
      '3. When counting items, count ONLY the records listed below. Do not estimate or guess.\n'
      '4. Return stored data verbatim — do not modify, censor, or omit any fields.\n'
      '5. When you find a matching record, wrap its title in double brackets: [[Record Title]]\n'
      '6. Include all fields (label, value, link, memo) in your response.\n'
      '7. When answering from DOCUMENT EXCERPTS, cite the document title and summarize the relevant content.\n'
      '8. You may also have general conversations, but NEVER pretend to have vault data that is not listed below.\n\n'
      'Example:\n'
      'User: "Find my GitHub info"\n'
      'Response: "Here is your GitHub record: [[GitHub Personal]]\n'
      '- Label: dev_account\n'
      '- Value: gh_abc123xyz\n'
      '- Link: github.com"\n\n'
      'Use markdown formatting for code blocks, lists, and emphasis.';

  static const mcpToolsPromptSuffix = '\n\n'
      'IMPORTANT — EXTERNAL TOOLS:\n'
      'You have access to external tools provided via MCP (Model Context Protocol) servers. '
      'When the user asks a question that is NOT about their vault records but could be answered by one of the available tools, '
      'you MUST use the appropriate tool to fetch the information. Do NOT say "I don\'t see that in your vault" '
      'if a tool can answer the question.\n\n'
      'Guidelines for tool use:\n'
      '1. For questions about vault records (secrets, notes, ideas, documents) — answer from the USER RECORDS section.\n'
      '2. For questions about external topics where a tool can help — USE THE TOOL. Call it and present the results to the user.\n'
      '3. You may call multiple tools or call a tool multiple times if needed to fully answer the question.\n'
      '4. Present tool results clearly with markdown formatting.\n'
      '5. If a tool call fails, let the user know and suggest alternatives.\n';

  /// Build a text summary of all vault contents for the LLM context.
  /// Uses neutral terminology to avoid triggering safety filters in small models.
  String buildVaultContext(
    List<VaultEntry> entries,
    List<Note> notes, {
    List<Idea>? ideas,
    List<db.DocumentChunk>? documentChunks,
    List<String> documentTitles = const [],
    List<ChatSession>? chatSessions,
  }) {
    final buf = StringBuffer();
    buf.writeln('=== USER RECORDS ===');

    // Provide explicit counts so the model can answer "how many" accurately
    final ideaCount = ideas?.length ?? 0;
    buf.writeln('SUMMARY: ${entries.length} secret(s), ${notes.length} note(s), $ideaCount idea(s)');
    if (documentChunks != null && documentChunks.isNotEmpty) {
      buf.writeln('  + ${documentChunks.length} document chunk(s) from ${documentTitles.length} document(s)');
    }
    if (chatSessions != null && chatSessions.isNotEmpty) {
      buf.writeln('  + ${chatSessions.length} past conversation(s)');
    }
    buf.writeln();

    if (entries.isEmpty && notes.isEmpty) {
      buf.writeln('No records stored.');
      return buf.toString();
    }

    if (entries.isNotEmpty) {
      buf.writeln('--- SAVED ITEMS (${entries.length}) ---');
      for (final e in entries) {
        buf.writeln('Record: "${e.title}"');
        if (e.category.isNotEmpty) buf.writeln('  Type: ${e.category}');
        if (e.username.isNotEmpty) buf.writeln('  Label: ${e.username}');
        if (e.password.isNotEmpty) buf.writeln('  Value: ${e.password}');
        if (e.url.isNotEmpty) buf.writeln('  Link: ${e.url}');
        if (e.tags.isNotEmpty) buf.writeln('  Tags: ${e.tags}');
        if (e.notes.isNotEmpty) buf.writeln('  Memo: ${e.notes}');
        final dateStr = '${e.updatedAt.year}-${e.updatedAt.month.toString().padLeft(2, '0')}-${e.updatedAt.day.toString().padLeft(2, '0')}';
        buf.writeln('  Modified: $dateStr');
        if (e.expiresAt != null) {
          final expDate = '${e.expiresAt!.year}-${e.expiresAt!.month.toString().padLeft(2, '0')}-${e.expiresAt!.day.toString().padLeft(2, '0')}';
          if (e.isExpired) {
            buf.writeln('  Status: EXPIRED on $expDate');
          } else if (e.isExpiringSoon) {
            final daysLeft = e.expiresAt!.difference(DateTime.now()).inDays;
            buf.writeln('  Status: Expiring on $expDate ($daysLeft days left)');
          } else {
            buf.writeln('  Expires: $expDate');
          }
        }
        buf.writeln();
      }
    }

    if (notes.isNotEmpty) {
      buf.writeln('--- NOTES (${notes.length}) ---');
      for (final n in notes) {
        buf.writeln('Note: "${n.title}"');
        if (n.tags.isNotEmpty) buf.writeln('  Tags: ${n.tags}');
        if (n.body.isNotEmpty) {
          final preview = n.body.length > 300
              ? '${n.body.substring(0, 300)}...'
              : n.body;
          buf.writeln('  Content: $preview');
        }
        final dateStr = '${n.updatedAt.year}-${n.updatedAt.month.toString().padLeft(2, '0')}-${n.updatedAt.day.toString().padLeft(2, '0')}';
        buf.writeln('  Modified: $dateStr');
        buf.writeln();
      }
    }

    if (ideas != null && ideas.isNotEmpty) {
      buf.writeln('--- IDEAS (${ideas.length}) ---');
      for (final i in ideas) {
        buf.writeln('Idea: "${i.title}"');
        if (i.tags.isNotEmpty) buf.writeln('  Tags: ${i.tags}');
        if (i.body.isNotEmpty) {
          final preview = i.body.length > 300
              ? '${i.body.substring(0, 300)}...'
              : i.body;
          buf.writeln('  Content: $preview');
        }
        final dateStr = '${i.updatedAt.year}-${i.updatedAt.month.toString().padLeft(2, '0')}-${i.updatedAt.day.toString().padLeft(2, '0')}';
        buf.writeln('  Modified: $dateStr');
        buf.writeln();
      }
    }

    if (documentChunks != null && documentChunks.isNotEmpty) {
      buf.writeln(
          '--- DOCUMENT EXCERPTS (${documentChunks.length} chunks) ---');
      if (documentTitles.isNotEmpty) {
        buf.writeln('Source documents: ${documentTitles.join(', ')}');
        buf.writeln();
      }
      for (final chunk in documentChunks) {
        buf.writeln(
            'Document chunk ${chunk.chunkIndex + 1} (from document ID: ${chunk.documentId}):');
        buf.writeln(chunk.content);
        buf.writeln();
      }
    }

    if (chatSessions != null && chatSessions.isNotEmpty) {
      buf.writeln(
          '--- PAST CONVERSATIONS (${chatSessions.length}) ---');
      for (final session in chatSessions) {
        final dateStr =
            '${session.updatedAt.year}-${session.updatedAt.month.toString().padLeft(2, '0')}-${session.updatedAt.day.toString().padLeft(2, '0')}';
        buf.writeln('Chat: "${session.title}" (from $dateStr)');
        // Include up to 10 messages for context
        final msgs = session.messages.take(10).toList();
        for (final msg in msgs) {
          final role = msg.isUser ? 'User' : 'Assistant';
          final text = msg.text.length > 200
              ? '${msg.text.substring(0, 200)}...'
              : msg.text;
          buf.writeln('  $role: $text');
        }
        if (session.messages.length > 10) {
          buf.writeln(
              '  ... (${session.messages.length - 10} more messages)');
        }
        buf.writeln();
      }
    }

    buf.writeln('=== END RECORDS ===');
    return buf.toString();
  }

  /// Parse the LLM response for [[Item Name]] references and match them
  /// against entries and notes to determine which cards to show.
  ({List<VaultEntry> entries, List<Note> notes, List<Idea> ideas}) extractReferencedItems(
    String response,
    List<VaultEntry> allEntries,
    List<Note> allNotes,
    List<Idea> allIdeas,
  ) {
    final bracketPattern = RegExp(r'\[\[(.+?)\]\]');
    final matches = bracketPattern.allMatches(response);
    final referencedNames = matches
        .map((m) => m.group(1)!.toLowerCase())
        .toSet();

    if (referencedNames.isEmpty) {
      return (entries: <VaultEntry>[], notes: <Note>[], ideas: <Idea>[]);
    }

    final matchedEntries = allEntries.where((e) {
      final titleLower = e.title.toLowerCase();
      return referencedNames.any((name) =>
          titleLower == name ||
          titleLower.contains(name) ||
          name.contains(titleLower));
    }).toList();

    final matchedNotes = allNotes.where((n) {
      final titleLower = n.title.toLowerCase();
      return referencedNames.any((name) =>
          titleLower == name ||
          titleLower.contains(name) ||
          name.contains(titleLower));
    }).toList();

    final matchedIdeas = allIdeas.where((i) {
      final titleLower = i.title.toLowerCase();
      return referencedNames.any((name) =>
          titleLower == name ||
          titleLower.contains(name) ||
          name.contains(titleLower));
    }).toList();

    return (entries: matchedEntries, notes: matchedNotes, ideas: matchedIdeas);
  }

  /// Build a human-readable summary of RAG sources used.
  List<String> buildRagSourceSummary(
    List<VaultEntry>? ragEntries,
    List<Note>? ragNotes,
    List<Idea>? ragIdeas,
    List<db.DocumentChunk>? ragChunks,
    List<String> documentTitles,
    List<ChatSession>? chatSessions,
  ) {
    final sources = <String>[];
    if (ragEntries != null && ragEntries.isNotEmpty) {
      sources.add('${ragEntries.length} secret${ragEntries.length == 1 ? '' : 's'}');
    }
    if (ragNotes != null && ragNotes.isNotEmpty) {
      sources.add('${ragNotes.length} note${ragNotes.length == 1 ? '' : 's'}');
    }
    if (ragIdeas != null && ragIdeas.isNotEmpty) {
      sources.add('${ragIdeas.length} idea${ragIdeas.length == 1 ? '' : 's'}');
    }
    if (ragChunks != null && ragChunks.isNotEmpty) {
      final chunkCount = ragChunks.length;
      final docCount = documentTitles.length;
      sources.add(
        '$chunkCount chunk${chunkCount == 1 ? '' : 's'} from $docCount doc${docCount == 1 ? '' : 's'}',
      );
    }
    if (chatSessions != null && chatSessions.isNotEmpty) {
      sources.add(
        '${chatSessions.length} past chat${chatSessions.length == 1 ? '' : 's'}',
      );
    }
    return sources;
  }

  /// Strip [[brackets]] from the response text for display.
  String cleanResponse(String response) {
    return response.replaceAllMapped(
      RegExp(r'\[\[(.+?)\]\]'),
      (m) => m.group(1)!,
    );
  }

  /// Main chat method — sends query to the LLM with vault context.
  /// When [ragEntries] and [ragNotes] are provided (from RAG pipeline),
  /// only those items are included in the context instead of all items.
  Future<ChatResponse> chat(
    String query,
    List<ChatMessage> history,
    List<VaultEntry> entries,
    List<Note> notes,
    List<Idea> ideas, {
    List<VaultEntry>? ragEntries,
    List<Note>? ragNotes,
    List<Idea>? ragIdeas,
    List<db.DocumentChunk>? ragChunks,
    List<String> ragDocumentTitles = const [],
    List<ChatSession>? ragChatSessions,
    bool ragUsed = false,
  }) async {
    final aiStatus = await checkStatus();
    final aiOnline = aiStatus.status == OllamaConnectionStatus.ready;

    if (!aiOnline) {
      return ChatResponse(
        text: "I'm currently offline. Connect Ollama to chat with me!",
        aiOnline: false,
      );
    }

    // Build vault context — use RAG-filtered items if available.
    // If RAG was used but found nothing relevant, fall back to full vault
    // so the model can still answer broad questions like "how many secrets?"
    final contextEntries = (ragEntries != null && ragEntries.isNotEmpty)
        ? ragEntries
        : entries;
    final contextNotes = (ragNotes != null && ragNotes.isNotEmpty)
        ? ragNotes
        : notes;
    final contextIdeas = (ragIdeas != null && ragIdeas.isNotEmpty)
        ? ragIdeas
        : ideas;
    final vaultContext = buildVaultContext(
      contextEntries,
      contextNotes,
      ideas: contextIdeas,
      documentChunks: ragChunks,
      documentTitles: ragDocumentTitles,
      chatSessions: ragChatSessions,
    );

    // Build messages with system prompt + vault context + history + query
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '$systemPrompt\n\n$vaultContext',
      },
      ...history.map((m) => {
            'role': m.isUser ? 'user' : 'assistant',
            'content': m.text,
          }),
      {'role': 'user', 'content': query},
    ];

    final response = await _chatWithHistory(messages);
    if (response == null) {
      return ChatResponse(
        text: "Sorry, I couldn't process that. Try again?",
        aiOnline: true,
      );
    }

    // Extract [[referenced items]] from the response
    final referenced = extractReferencedItems(response, entries, notes, ideas);
    final cleanText = cleanResponse(response);

    return ChatResponse(
      text: cleanText,
      matchedEntries: referenced.entries,
      matchedNotes: referenced.notes,
      matchedIdeas: referenced.ideas,
      aiOnline: true,
      isVaultResult: referenced.entries.isNotEmpty || referenced.notes.isNotEmpty || referenced.ideas.isNotEmpty,
      ragUsed: ragUsed,
      ragSources: buildRagSourceSummary(
        ragEntries, ragNotes, ragIdeas, ragChunks, ragDocumentTitles, ragChatSessions,
      ),
    );
  }

  /// Check if the current model supports tool/function calling.
  Future<bool> supportsTools() async {
    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/show'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': _model}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return false;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final template = json['template'] as String? ?? '';

      // Check if model template includes tool handling
      if (template.contains('.Tools') || template.contains('tool_call')) {
        return true;
      }

      // Heuristic fallback based on known model families
      final modelLower = _model.toLowerCase();
      return _toolCapableFamilies.any((f) => modelLower.contains(f));
    } catch (_) {
      return false;
    }
  }

  static const _toolCapableFamilies = [
    'llama3.1', 'llama3.2', 'llama3.3', 'llama4',
    'qwen2.5', 'qwen3',
    'mistral', 'command-r',
    'firefunction', 'hermes',
    'granite',
  ];

  /// Send a chat request with tools. Returns either a text response or tool call requests.
  Future<AiToolResponse> chatWithTools(
    List<Map<String, dynamic>> messages, {
    List<Map<String, dynamic>>? tools,
  }) async {
    try {
      final body = <String, dynamic>{
        'model': _model,
        'messages': messages,
        'stream': false,
        'options': {'temperature': 0.2},
      };

      if (tools != null && tools.isNotEmpty) {
        body['tools'] = tools;
      }

      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        return AiToolResponse.withError(
          'Ollama returned status ${response.statusCode}',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final message = json['message'] as Map<String, dynamic>?;
      if (message == null) {
        return AiToolResponse.withError('No message in response');
      }

      final toolCalls = message['tool_calls'] as List<dynamic>?;
      final content = message['content'] as String? ?? '';

      if (toolCalls != null && toolCalls.isNotEmpty) {
        final calls = toolCalls.map((tc) {
          final fn = tc['function'] as Map<String, dynamic>;
          final args = fn['arguments'];
          return ToolCallRequest(
            name: fn['name'] as String,
            arguments: args is Map<String, dynamic>
                ? args
                : <String, dynamic>{},
          );
        }).toList();
        return AiToolResponse.toolCalls(calls);
      }

      return AiToolResponse.text(content);
    } catch (e) {
      return AiToolResponse.withError(e.toString());
    }
  }

  /// Send a multi-turn conversation to the LLM
  Future<String?> _chatWithHistory(List<Map<String, String>> messages) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': _model,
              'messages': messages,
              'stream': false,
              'options': {
                'temperature': 0.2,
              },
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final message = json['message'] as Map<String, dynamic>?;
      return message?['content'] as String?;
    } catch (_) {
      return null;
    }
  }
}

enum OllamaConnectionStatus {
  ollamaNotRunning,
  modelNotFound,
  ready,
}

class OllamaStatus {
  final OllamaConnectionStatus status;
  final List<String> availableModels;

  const OllamaStatus({
    required this.status,
    this.availableModels = const [],
  });
}

/// A single message in the chat conversation
class ChatMessage {
  final String text;
  final bool isUser;
  final List<VaultEntry> matchedEntries;
  final List<Note> matchedNotes;
  final List<Idea> matchedIdeas;
  final bool aiOnline;
  final bool isVaultResult;
  final bool ragUsed;
  final List<String> ragSources;
  final List<ToolCallInfo> toolCalls;
  final bool mcpUsed;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.matchedEntries = const [],
    this.matchedNotes = const [],
    this.matchedIdeas = const [],
    this.aiOnline = true,
    this.isVaultResult = false,
    this.ragUsed = false,
    this.ragSources = const [],
    this.toolCalls = const [],
    this.mcpUsed = false,
  });
}

/// Response from the chat method
class ChatResponse {
  final String text;
  final List<VaultEntry> matchedEntries;
  final List<Note> matchedNotes;
  final List<Idea> matchedIdeas;
  final bool aiOnline;
  final bool isVaultResult;
  final bool ragUsed;
  final List<String> ragSources;
  final List<ToolCallInfo> toolCalls;
  final bool mcpUsed;

  const ChatResponse({
    required this.text,
    this.matchedEntries = const [],
    this.matchedNotes = const [],
    this.matchedIdeas = const [],
    this.aiOnline = true,
    this.isVaultResult = false,
    this.ragUsed = false,
    this.ragSources = const [],
    this.toolCalls = const [],
    this.mcpUsed = false,
  });
}
