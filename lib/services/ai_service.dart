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

  /// Detect if a query is a "meta query" — asking about the vault itself
  /// rather than searching for a specific entry.
  /// Returns a filtered list of entries if it's a meta query, or null if not.
  _MetaQueryResult? _detectMetaQuery(
    String queryLower,
    List<VaultEntry> entries,
  ) {
    // --- Expiration queries ---
    final expirationPatterns = [
      'expired', 'expiring', 'expiration', 'expire',
      'out of date', 'outdated', 'old secrets', 'stale',
    ];
    final isExpirationQuery = expirationPatterns.any(
      (p) => queryLower.contains(p),
    );

    if (isExpirationQuery) {
      // Check if they specifically want "expiring soon" vs "expired"
      final wantExpiringSoon = queryLower.contains('expiring soon') ||
          queryLower.contains('about to expire') ||
          queryLower.contains('expiring');
      final wantExpired = queryLower.contains('expired') ||
          queryLower.contains('out of date') ||
          queryLower.contains('outdated') ||
          queryLower.contains('stale');

      List<VaultEntry> filtered;
      if (wantExpiringSoon && !wantExpired) {
        filtered = entries.where((e) => e.isExpiringSoon).toList()
          ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));
      } else if (wantExpired && !wantExpiringSoon) {
        filtered = entries.where((e) => e.isExpired).toList()
          ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));
      } else {
        // Both or ambiguous — show expired + expiring soon
        filtered = entries
            .where((e) => e.isExpired || e.isExpiringSoon)
            .toList()
          ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));
      }

      return _MetaQueryResult(
        entries: filtered,
        queryType: 'expiration',
      );
    }

    // --- Recent / latest queries ---
    final recentPatterns = [
      'recent', 'latest', 'last added', 'newest', 'just added',
      'last updated', 'recently',
    ];
    final isRecentQuery = recentPatterns.any((p) => queryLower.contains(p));

    if (isRecentQuery) {
      final sorted = [...entries]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return _MetaQueryResult(
        entries: sorted.take(5).toList(),
        queryType: 'recent',
      );
    }

    // --- "How many" / count queries ---
    final countPatterns = [
      'how many', 'count', 'total', 'number of',
    ];
    final isCountQuery = countPatterns.any((p) => queryLower.contains(p));

    if (isCountQuery) {
      // Return all entries — the AI will summarize
      return _MetaQueryResult(
        entries: entries,
        queryType: 'count',
      );
    }

    // --- "Show all" / category listing queries ---
    final allPatterns = [
      'show all', 'list all', 'all my', 'everything',
      'all secrets', 'all entries', 'what do i have',
    ];
    final isAllQuery = allPatterns.any((p) => queryLower.contains(p));

    if (isAllQuery) {
      // Check if they want a specific category
      final impliedCategory = _detectCategory(queryLower);
      List<VaultEntry> filtered;
      if (impliedCategory != null) {
        filtered = entries
            .where((e) =>
                e.category.toLowerCase() == impliedCategory.toLowerCase())
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } else {
        filtered = [...entries]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
      return _MetaQueryResult(
        entries: filtered.take(10).toList(),
        queryType: 'listing',
      );
    }

    return null;
  }

  /// Build a meta query response — summarizes vault state rather than
  /// searching for a specific entry.
  String _buildMetaFallbackResponse(
    String query,
    _MetaQueryResult meta,
  ) {
    final entries = meta.entries;
    final buf = StringBuffer();

    switch (meta.queryType) {
      case 'expiration':
        final expiredCount = entries.where((e) => e.isExpired).length;
        final expiringCount = entries.where((e) => e.isExpiringSoon).length;
        if (entries.isEmpty) {
          buf.write(
            'Good news! None of your secrets are expired or expiring soon.',
          );
        } else {
          if (expiredCount > 0) {
            buf.write(
              'You have $expiredCount expired '
              '${expiredCount == 1 ? "secret" : "secrets"}. ',
            );
          }
          if (expiringCount > 0) {
            buf.write(
              '$expiringCount ${expiringCount == 1 ? "is" : "are"} '
              'expiring soon. ',
            );
          }
          buf.write('Here they are:');
        }
      case 'recent':
        buf.write(
          'Here are your ${entries.length} most recently updated secrets:',
        );
      case 'count':
        buf.write('You have ${entries.length} secrets in your vault.');
        // Add category breakdown
        final categories = <String, int>{};
        for (final e in entries) {
          categories[e.category] = (categories[e.category] ?? 0) + 1;
        }
        if (categories.isNotEmpty) {
          final breakdown = categories.entries
              .map((e) => '${e.key}: ${e.value}')
              .join(', ');
          buf.write(' Breakdown: $breakdown.');
        }
      case 'listing':
        buf.write(
          'Here are ${entries.length} entries from your vault:',
        );
      default:
        buf.write('Here is what I found:');
    }

    return buf.toString();
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

    // Step 2: Check if this is a meta query (about the vault itself)
    final queryLower = query.toLowerCase();
    final metaResult = _detectMetaQuery(queryLower, entries);

    if (metaResult != null) {
      final matchedEntries = metaResult.entries;

      String response;
      if (aiOnline) {
        response = await _generateMetaResponse(
          query, metaResult,
        ) ?? _buildMetaFallbackResponse(query, metaResult);
      } else {
        response = _buildMetaFallbackResponse(query, metaResult);
      }

      return AiSearchResult(
        response: response,
        matchedEntries: matchedEntries,
        aiOnline: aiOnline,
      );
    }

    // Step 3: Try to get LLM-enhanced keywords (only if AI is online)
    List<String> keywords = [];
    if (aiOnline) {
      keywords = await _extractKeywords(query);
    }

    // Step 4: Score and rank entries using keywords + original query
    final scored = _scoreEntries(query, keywords, entries);

    // Step 5: Take top 3 matches (sorted by score desc, then by date desc)
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
        response = "I couldn't find anything matching \"$query\". Note: AI is offline - connect Ollama for smarter search results.";
      }
      return AiSearchResult(
        response: response,
        matchedEntries: [],
        aiOnline: aiOnline,
      );
    }

    // Step 6: Generate a conversational AI response wrapping the results
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

  /// Generate an AI response specifically for meta queries (expiration, counts, etc.)
  /// Uses a tailored prompt so the LLM only talks about what was asked.
  Future<String?> _generateMetaResponse(
    String query,
    _MetaQueryResult meta,
  ) async {
    final entries = meta.entries;

    if (entries.isEmpty) {
      // Let the LLM give a friendly "nothing found" for the specific query type
      final context = switch (meta.queryType) {
        'expiration' => 'None of the user\'s secrets are expired or expiring soon.',
        'recent' => 'The user has no secrets in their vault yet.',
        'count' => 'The user\'s vault is empty.',
        'listing' => 'No entries matched the user\'s request.',
        _ => 'No matching entries were found.',
      };

      return _askLlm(
        '$_systemPrompt\n\n'
        'The user asked: "$query"\n\n'
        '$context\n'
        'Respond with a brief, friendly message (1-2 sentences). '
        'Do NOT use markdown formatting.',
      );
    }

    final entrySummaries = entries.map((e) {
      final parts = <String>['Title: ${e.title}'];
      if (e.category.isNotEmpty) parts.add('Category: ${e.category}');
      if (e.expiresAt != null) {
        final expDate = '${e.expiresAt!.year}-${e.expiresAt!.month.toString().padLeft(2, '0')}-${e.expiresAt!.day.toString().padLeft(2, '0')}';
        if (e.isExpired) {
          final daysAgo = DateTime.now().difference(e.expiresAt!).inDays;
          parts.add('EXPIRED on $expDate ($daysAgo days ago)');
        } else if (e.isExpiringSoon) {
          final daysLeft = e.expiresAt!.difference(DateTime.now()).inDays;
          parts.add('Expiring on $expDate ($daysLeft days left)');
        } else {
          parts.add('Expires: $expDate');
        }
      }
      return parts.join(', ');
    }).join('\n');

    final queryContext = switch (meta.queryType) {
      'expiration' => 'These are the secrets that are expired or expiring soon. '
          'ONLY talk about their expiration status. '
          'Do NOT mention update dates or other unrelated details.',
      'recent' => 'These are the most recently updated secrets. '
          'Briefly mention when they were last updated.',
      'count' => 'The user is asking about how many secrets they have. '
          'Summarize the count and categories.',
      'listing' => 'The user wants to see their secrets. '
          'Briefly acknowledge what you are showing them.',
      _ => 'Summarize what you found.',
    };

    return _askLlm(
      '$_systemPrompt\n\n'
      'The user asked: "$query"\n\n'
      'Here are the ${entries.length} relevant entries:\n$entrySummaries\n\n'
      '$queryContext\n'
      'Write a brief, friendly response (1-2 sentences max). '
      'Reference entries by name. '
      'Do NOT mention entries or details that are not listed above. '
      'Do NOT use markdown formatting.',
    );
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

  /// Map of category-implying keywords to their actual category names.
  /// When the user's query contains these words, we know what category they want.
  static const _categorySignals = <String, String>{
    'api key': 'API Key',
    'apikey': 'API Key',
    'api keys': 'API Key',
    'apikeys': 'API Key',
    'api token': 'API Key',
    'token': 'API Key',
    'password': 'Login',
    'login': 'Login',
    'credential': 'Login',
    'credentials': 'Login',
    'credit card': 'Credit Card',
    'card': 'Credit Card',
    'ssh': 'SSH Key',
    'ssh key': 'SSH Key',
    'private key': 'SSH Key',
    'public key': 'SSH Key',
    'wifi': 'WiFi',
    'wireless': 'WiFi',
    'network': 'WiFi',
    'note': 'Note',
    'secure note': 'Note',
  };

  /// Words that are generic category/type descriptors, not identity keywords.
  /// These should NOT be used to match entry titles/content — only for
  /// category filtering.
  static final _genericWords = <String>{
    'api', 'key', 'keys', 'apikey', 'apikeys', 'token', 'tokens',
    'password', 'passwords', 'login', 'logins', 'credential', 'credentials',
    'credit', 'card', 'ssh', 'wifi', 'wireless', 'network',
    'note', 'notes', 'secret', 'secrets',
    'find', 'show', 'get', 'give', 'need', 'want', 'where', 'what',
    'my', 'the', 'for', 'me',
  };

  /// Detect which category the user is asking about based on their query.
  String? _detectCategory(String queryLower) {
    // Check longer phrases first to avoid partial matches
    final sortedSignals = _categorySignals.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final signal in sortedSignals) {
      if (queryLower.contains(signal)) {
        return _categorySignals[signal];
      }
    }
    return null;
  }

  /// Extract identity keywords — words that identify WHICH specific entry
  /// the user wants (e.g., "anthropic", "github", "stripe"), filtering out
  /// generic category/type words.
  List<String> _extractIdentityWords(List<String> queryWords) {
    return queryWords
        .where((w) => !_genericWords.contains(w) && w.length > 1)
        .toList();
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

    // Detect if the query implies a specific category
    final impliedCategory = _detectCategory(queryLower);

    // Separate identity words from generic words
    final identityWords = _extractIdentityWords(queryWords);

    // Also extract identity words from LLM keywords
    final llmIdentityWords = keywords
        .where((k) => !_genericWords.contains(k) && k.length > 1)
        .toList();

    // All identity keywords combined (what makes this entry unique)
    final allIdentity = <String>{...identityWords, ...llmIdentityWords}.toList();

    // All keywords for general matching
    final allKeywords = <String>{...keywords, ...queryWords}.toList();

    return entries.map((entry) {
      double score = 0;

      final title = entry.title.toLowerCase();
      final tags = entry.tags.toLowerCase();
      final notes = entry.notes.toLowerCase();
      final username = entry.username.toLowerCase();
      final url = entry.url.toLowerCase();

      // --- Category matching ---
      if (impliedCategory != null) {
        if (entry.category.toLowerCase() ==
            impliedCategory.toLowerCase()) {
          // Entry is in the right category — bonus
          score += 15;
        } else {
          // Entry is in the WRONG category — significant penalty
          score -= 20;
        }
      }

      // --- Identity keyword matching (the important part) ---
      int identityHits = 0;
      for (final keyword in allIdentity) {
        bool matched = false;
        if (title.contains(keyword)) {
          score += 15;
          matched = true;
        }
        if (tags.contains(keyword)) {
          score += 8;
          matched = true;
        }
        if (username.contains(keyword)) {
          score += 6;
          matched = true;
        }
        if (url.contains(keyword)) {
          score += 6;
          matched = true;
        }
        if (notes.contains(keyword)) {
          score += 3;
          matched = true;
        }
        if (matched) {
          identityHits++;
        }
      }

      // If there are identity keywords but NONE matched this entry,
      // it's almost certainly not what the user wants
      if (allIdentity.isNotEmpty && identityHits == 0) {
        score -= 10;
      }

      // Bonus for matching ALL identity keywords (not just some)
      if (allIdentity.isNotEmpty && identityHits == allIdentity.length) {
        score += 10;
      }

      // --- General keyword matching (lower weight, for broad relevance) ---
      for (final keyword in allKeywords) {
        // Skip generic words for title/content matching — they only matter
        // for category, which we already handled above
        if (_genericWords.contains(keyword)) continue;

        // Only give additional points if not already counted as identity
        if (!allIdentity.contains(keyword)) {
          if (title.contains(keyword)) score += 5;
          if (tags.contains(keyword)) score += 3;
          if (username.contains(keyword)) score += 2;
          if (url.contains(keyword)) score += 2;
          if (notes.contains(keyword)) score += 1;
        }
      }

      // Exact title match bonus
      if (title == queryLower) score += 25;

      // Partial title match bonus
      if (title.contains(queryLower) || queryLower.contains(title)) {
        score += 8;
      }

      // Check for fuzzy word overlap between query identity words and title
      final titleWords = title
          .split(RegExp(r'[\s,.\-_]+'))
          .where((w) => w.length > 1);
      for (final tw in titleWords) {
        for (final qw in identityWords) {
          if (tw == qw) {
            score += 10;
          } else if (tw.contains(qw) || qw.contains(tw)) {
            score += 5;
          } else if (_levenshtein(tw, qw) <= 2) {
            score += 4; // typo tolerance
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

class _MetaQueryResult {
  final List<VaultEntry> entries;
  final String queryType; // 'expiration', 'recent', 'count', 'listing'

  _MetaQueryResult({required this.entries, required this.queryType});
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
