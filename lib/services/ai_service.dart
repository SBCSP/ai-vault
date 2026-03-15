import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

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

  /// Simple connection test - now checks both Ollama AND model availability.
  Future<bool> testConnection() async {
    final status = await checkStatus();
    return status.status == OllamaConnectionStatus.ready;
  }

  /// Full status check: is Ollama running? Is the configured model available?
  Future<OllamaStatus> checkStatus() async {
    // Step 1: Check if Ollama server is reachable
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

      // Parse the list of locally available models
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

    // Step 2: Check if the configured model is in the list
    final modelLower = _model.toLowerCase();
    final hasModel = availableModels.any((m) {
      final mLower = m.toLowerCase();
      // Match "gemma3:1b" against "gemma3:1b", or partial name matches
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

  Future<AiSearchResult> searchVault(
    String query,
    List<VaultEntry> entries,
  ) async {
    if (entries.isEmpty) {
      return AiSearchResult(
        response: 'Your vault is empty. Add some entries first!',
        matchedEntries: [],
        aiOnline: false,
      );
    }

    // Step 1: Verify the AI is actually reachable
    final aiStatus = await checkStatus();
    final aiOnline = aiStatus.status == OllamaConnectionStatus.ready;

    // Step 2: Try to get LLM-enhanced keywords (only if AI is online)
    List<String> keywords = [];
    if (aiOnline) {
      keywords = await _extractKeywords(query);
    }

    // If AI is offline and we got no keywords, we can still do basic search
    // but we'll flag it clearly

    // Step 3: Score and rank entries using keywords + original query
    final scored = _scoreEntries(query, keywords, entries);

    // Step 4: Take top 3 matches (sorted by score desc, then by date desc)
    scored.sort((a, b) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      return b.entry.updatedAt.compareTo(a.entry.updatedAt);
    });

    final topMatches = scored.where((s) => s.score > 0).take(3).toList();

    if (topMatches.isEmpty) {
      // Ask AI for a helpful response if online
      String response;
      if (aiOnline) {
        final suggestion = await _askLlm(
          '$_systemPrompt\n'
          'The user asked: "$query"\n'
          'No matching entries were found in their vault.\n'
          'Respond helpfully - suggest what they might search for or '
          'remind them they can add a new entry. Keep it to 1-2 sentences. '
          'Be warm and helpful.',
        );
        response = suggestion ?? "I couldn't find anything matching \"$query\" in your vault. Try different keywords, or add a new entry with the + button!";
      } else {
        response = "I couldn't find anything matching \"$query\". Note: AI is offline — connect Ollama for smarter search results.";
      }
      return AiSearchResult(
        response: response,
        matchedEntries: [],
        aiOnline: aiOnline,
      );
    }

    // Step 5: Generate a conversational AI response wrapping the results
    final matchedEntries = topMatches.map((s) => s.entry).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    String response;
    if (aiOnline) {
      response = await _generateConversationalResponse(
        query, matchedEntries,
      ) ?? _buildFallbackResponse(query, matchedEntries);
    } else {
      response = _buildFallbackResponse(query, matchedEntries);
    }

    return AiSearchResult(
      response: response,
      matchedEntries: matchedEntries,
      aiOnline: aiOnline,
    );
  }

  static const _systemPrompt = 'You are the AI assistant inside AI Vault, a personal secrets manager. '
      'You help users find their passwords, API keys, SSH keys, and other secrets. '
      'You are friendly, concise, and security-conscious. '
      'Speak in first person. Be warm but professional. '
      'Never reveal secrets in your text response - the app UI shows them separately with copy buttons. '
      'Instead, reference entries by name and give helpful context.';

  /// Ask the LLM to generate a conversational response about matched entries
  Future<String?> _generateConversationalResponse(
    String query,
    List<VaultEntry> matches,
  ) async {
    final entrySummaries = matches.map((e) {
      final parts = <String>['Title: ${e.title}'];
      if (e.category.isNotEmpty) parts.add('Category: ${e.category}');
      if (e.username.isNotEmpty) parts.add('Username: ${e.username}');
      if (e.url.isNotEmpty) parts.add('URL: ${e.url}');
      if (e.tags.isNotEmpty) parts.add('Tags: ${e.tags}');
      final dateStr = '${e.updatedAt.year}-${e.updatedAt.month.toString().padLeft(2, '0')}-${e.updatedAt.day.toString().padLeft(2, '0')}';
      parts.add('Last updated: $dateStr');
      if (e.isExpired) {
        parts.add('⚠️ THIS SECRET IS EXPIRED');
      } else if (e.isExpiringSoon) {
        parts.add('⚠️ Expiring soon');
      }
      return parts.join(', ');
    }).join('\n');

    final prompt = '$_systemPrompt\n\n'
        'The user asked: "$query"\n\n'
        'I found ${matches.length} matching ${matches.length == 1 ? "entry" : "entries"} '
        '(most recent first):\n$entrySummaries\n\n'
        'Write a brief, friendly response (2-3 sentences max) acknowledging what you found. '
        'Reference the entries by name. If any are expired or expiring soon, mention that. '
        'If there are multiple results, note you\'re showing the most recent ones. '
        'The secrets themselves are shown in the UI below your message — don\'t try to show them. '
        'Do NOT use markdown formatting.';

    return _askLlm(prompt);
  }

  /// Fallback response when AI is offline — still friendly but simpler
  String _buildFallbackResponse(String query, List<VaultEntry> matches) {
    final count = matches.length;
    final buf = StringBuffer();

    if (count == 1) {
      final entry = matches.first;
      buf.write('I found "${entry.title}"');
      if (entry.category.isNotEmpty) {
        buf.write(' in ${entry.category}');
      }
      buf.write(' matching your request.');
      if (entry.isExpired) {
        buf.write(' ⚠️ Heads up — this secret is expired!');
      } else if (entry.isExpiringSoon) {
        buf.write(' ⚠️ Note: this one is expiring soon.');
      }
    } else {
      buf.write('I found $count entries matching "$query", '
          'showing the most recent first.');
      final expired = matches.where((e) => e.isExpired).length;
      final expiring = matches.where((e) => e.isExpiringSoon).length;
      if (expired > 0) {
        buf.write(' ⚠️ $expired ${expired == 1 ? "is" : "are"} expired.');
      }
      if (expiring > 0) {
        buf.write(' ⚠️ $expiring ${expiring == 1 ? "is" : "are"} expiring soon.');
      }
    }

    return buf.toString();
  }

  /// Ask the LLM to extract search keywords from the user's natural language query
  Future<List<String>> _extractKeywords(String query) async {
    final prompt = '''Extract search keywords from this request. Return ONLY a comma-separated list of keywords, nothing else.

Examples:
- "I need my anthropic apikey" → anthropic, api key, apikey
- "what's my netflix password" → netflix, password
- "find my AWS credentials" → aws, credentials, amazon
- "show me stripe keys" → stripe, key, api key

Request: "$query"
Keywords:''';

    final response = await _askLlm(prompt);
    if (response == null) return [];

    return response
        .split(',')
        .map((k) => k.trim().toLowerCase())
        .where((k) => k.isNotEmpty && k.length > 1)
        .toList();
  }

  /// Generic LLM call
  Future<String?> _askLlm(String prompt) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
              'stream': false,
              'options': {
                'temperature': 0.3,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final message = json['message'] as Map<String, dynamic>?;
      return message?['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Score each entry against keywords and the original query
  List<_ScoredEntry> _scoreEntries(
    String query,
    List<String> keywords,
    List<VaultEntry> entries,
  ) {
    final queryLower = query.toLowerCase();
    final queryWords = queryLower
        .split(RegExp(r'[\s,.\-_]+'))
        .where((w) => w.length > 1)
        .toList();

    // Combine query words with LLM-extracted keywords
    final allKeywords = <String>{...keywords, ...queryWords}.toList();

    return entries.map((entry) {
      double score = 0;

      final title = entry.title.toLowerCase();
      final category = entry.category.toLowerCase();
      final tags = entry.tags.toLowerCase();
      final notes = entry.notes.toLowerCase();
      final username = entry.username.toLowerCase();
      final url = entry.url.toLowerCase();

      for (final keyword in allKeywords) {
        // Title matches are most important
        if (title.contains(keyword)) score += 10;
        // Category match (e.g., "API Key" category)
        if (category.contains(keyword)) score += 8;
        // Tags match
        if (tags.contains(keyword)) score += 6;
        // Username/URL match
        if (username.contains(keyword)) score += 4;
        if (url.contains(keyword)) score += 4;
        // Notes match
        if (notes.contains(keyword)) score += 2;
      }

      // Exact title match bonus
      if (title == queryLower) score += 20;

      // Partial title match bonus (title contains query or vice versa)
      if (title.contains(queryLower) || queryLower.contains(title)) {
        score += 5;
      }

      // Check for fuzzy word overlap between query and title
      final titleWords = title.split(RegExp(r'[\s,.\-_]+')).where((w) => w.length > 1);
      for (final tw in titleWords) {
        for (final qw in queryWords) {
          if (tw == qw) {
            score += 8;
          } else if (tw.contains(qw) || qw.contains(tw)) {
            score += 4;
          } else if (_levenshtein(tw, qw) <= 2) {
            score += 3; // typo tolerance
          }
        }
      }

      return _ScoredEntry(entry: entry, score: score);
    }).toList();
  }

  /// Levenshtein distance for typo tolerance
  int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final matrix = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => 0),
    );

    for (var i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce(min);
      }
    }

    return matrix[a.length][b.length];
  }
}

class _ScoredEntry {
  final VaultEntry entry;
  final double score;

  _ScoredEntry({required this.entry, required this.score});
}

class AiSearchResult {
  final String response;
  final List<VaultEntry> matchedEntries;
  final bool aiOnline;

  /// Convenience getter for matched IDs (for highlighting in UI)
  List<String> get matchedIds => matchedEntries.map((e) => e.id).toList();

  AiSearchResult({
    required this.response,
    required this.matchedEntries,
    this.aiOnline = true,
  });
}

enum OllamaConnectionStatus {
  /// Ollama server is not reachable / not installed
  ollamaNotRunning,

  /// Ollama is running but the configured model is not downloaded
  modelNotFound,

  /// Ollama is running and the model is available
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
