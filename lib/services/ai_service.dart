import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/database.dart' as db;
import '../models/chat_session.dart';
import '../models/note.dart';
import '../models/vault_entry.dart';

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

  static const _systemPrompt = 'You are a personal vault assistant. '
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

  /// Build a text summary of all vault contents for the LLM context.
  /// Uses neutral terminology to avoid triggering safety filters in small models.
  String _buildVaultContext(
    List<VaultEntry> entries,
    List<Note> notes, {
    List<db.DocumentChunk>? documentChunks,
    List<String> documentTitles = const [],
    List<ChatSession>? chatSessions,
  }) {
    final buf = StringBuffer();
    buf.writeln('=== USER RECORDS ===');

    // Provide explicit counts so the model can answer "how many" accurately
    buf.writeln('SUMMARY: ${entries.length} secret(s), ${notes.length} note(s)');
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
  ({List<VaultEntry> entries, List<Note> notes}) _extractReferencedItems(
    String response,
    List<VaultEntry> allEntries,
    List<Note> allNotes,
  ) {
    final bracketPattern = RegExp(r'\[\[(.+?)\]\]');
    final matches = bracketPattern.allMatches(response);
    final referencedNames = matches
        .map((m) => m.group(1)!.toLowerCase())
        .toSet();

    if (referencedNames.isEmpty) {
      return (entries: <VaultEntry>[], notes: <Note>[]);
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

    return (entries: matchedEntries, notes: matchedNotes);
  }

  /// Build a human-readable summary of RAG sources used.
  List<String> _buildRagSourceSummary(
    List<VaultEntry>? ragEntries,
    List<Note>? ragNotes,
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
  String _cleanResponse(String response) {
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
    List<Note> notes, {
    List<VaultEntry>? ragEntries,
    List<Note>? ragNotes,
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
    final vaultContext = _buildVaultContext(
      contextEntries,
      contextNotes,
      documentChunks: ragChunks,
      documentTitles: ragDocumentTitles,
      chatSessions: ragChatSessions,
    );

    // Build messages with system prompt + vault context + history + query
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '$_systemPrompt\n\n$vaultContext',
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
    final referenced = _extractReferencedItems(response, entries, notes);
    final cleanText = _cleanResponse(response);

    return ChatResponse(
      text: cleanText,
      matchedEntries: referenced.entries,
      matchedNotes: referenced.notes,
      aiOnline: true,
      isVaultResult: referenced.entries.isNotEmpty || referenced.notes.isNotEmpty,
      ragUsed: ragUsed,
      ragSources: _buildRagSourceSummary(
        ragEntries, ragNotes, ragChunks, ragDocumentTitles, ragChatSessions,
      ),
    );
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
  final bool aiOnline;
  final bool isVaultResult;
  final bool ragUsed;
  final List<String> ragSources;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.matchedEntries = const [],
    this.matchedNotes = const [],
    this.aiOnline = true,
    this.isVaultResult = false,
    this.ragUsed = false,
    this.ragSources = const [],
  });
}

/// Response from the chat method
class ChatResponse {
  final String text;
  final List<VaultEntry> matchedEntries;
  final List<Note> matchedNotes;
  final bool aiOnline;
  final bool isVaultResult;
  final bool ragUsed;
  final List<String> ragSources;

  const ChatResponse({
    required this.text,
    this.matchedEntries = const [],
    this.matchedNotes = const [],
    this.aiOnline = true,
    this.isVaultResult = false,
    this.ragUsed = false,
    this.ragSources = const [],
  });
}
