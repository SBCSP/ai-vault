import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_service.dart';

/// Service for calling the Claude (Anthropic) API.
///
/// This is a cloud-based LLM — secrets are NEVER sent to this service.
/// The secrets lock is automatically engaged when this provider is active.
class ClaudeApiService {
  static const _apiUrl = 'https://api.anthropic.com/v1/messages';
  static const _modelsUrl = 'https://api.anthropic.com/v1/models';
  static const _apiVersion = '2023-06-01';
  static const defaultModel = 'claude-sonnet-4-20250514';
  static const _defaultModel = defaultModel;

  final String _apiKey;
  final String _model;

  ClaudeApiService({
    String apiKey = '',
    String model = _defaultModel,
  })  : _apiKey = apiKey,
        _model = model;

  String get apiKey => _apiKey;
  String get model => _model;
  bool get isConfigured => _apiKey.isNotEmpty;

  /// Static fallback model list used when the API is unconfigured or unreachable.
  static const fallbackModels = [
    ('claude-sonnet-4-20250514', 'Claude Sonnet 4', 'Fast & capable'),
    ('claude-opus-4-20250514', 'Claude Opus 4', 'Most intelligent'),
    ('claude-haiku-4-20250514', 'Claude Haiku 4', 'Fastest & most compact'),
  ];

  /// Fetches all available models from the Anthropic API with pagination.
  /// Returns a list of (modelId, displayName, createdAt) triples
  /// sorted by creation date descending (newest first).
  Future<List<(String, String)>> fetchModels() async {
    final allModels = <(String, String, String)>[];
    String? afterId;

    // Paginate through all results
    for (var page = 0; page < 10; page++) {
      final uri = Uri.parse(_modelsUrl).replace(queryParameters: {
        'limit': '100',
        if (afterId != null) 'after_id': afterId,
      });

      final response = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${_parseError(response)}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? [];

      for (final m in data) {
        final id = m['id'] as String;
        final displayName = m['display_name'] as String? ?? id;
        final createdAt = m['created_at'] as String? ?? '';
        allModels.add((id, displayName, createdAt));
      }

      final hasMore = json['has_more'] as bool? ?? false;
      if (!hasMore || data.isEmpty) break;
      afterId = json['last_id'] as String?;
      if (afterId == null) break;
    }

    if (allModels.isEmpty) throw Exception('No models returned');

    // Sort by creation date descending (newest first)
    allModels.sort((a, b) => b.$3.compareTo(a.$3));

    return allModels.map((m) => (m.$1, m.$2)).toList();
  }

  /// Test the API connection with a simple request.
  Future<bool> testConnection() async {
    if (!isConfigured) return false;
    try {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: _headers(),
            body: jsonEncode({
              'model': _model,
              'max_tokens': 10,
              'messages': [
                {'role': 'user', 'content': 'Hi'}
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Send a chat message to Claude API.
  /// Note: vault context should NOT include secrets when using cloud LLM.
  Future<ChatResponse> chat(
    String query,
    List<ChatMessage> history,
    String vaultContext,
  ) async {
    if (!isConfigured) {
      return const ChatResponse(
        text: 'Claude API key not configured. Go to Settings to add your API key.',
        aiOnline: false,
      );
    }

    try {
      // Build messages array — Claude API uses user/assistant roles only,
      // system prompt goes in the top-level 'system' field.
      final messages = <Map<String, String>>[
        ...history.map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.text,
            }),
        {'role': 'user', 'content': query},
      ];

      final systemPrompt =
          '${AiService.systemPrompt}\n\n'
          'IMPORTANT: You are running as a CLOUD model. Secrets have been automatically '
          'locked for security. You can access notes, ideas, and documents but NOT secrets. '
          'If the user asks about secrets, remind them to switch to a local Ollama model '
          'to access secrets securely.\n\n'
          '$vaultContext';

      final body = {
        'model': _model,
        'max_tokens': 4096,
        'system': systemPrompt,
        'messages': messages,
      };

      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        final error = _parseError(response);
        return ChatResponse(
          text: 'Claude API error: $error',
          aiOnline: false,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final content = json['content'] as List<dynamic>?;
      if (content == null || content.isEmpty) {
        return const ChatResponse(
          text: 'No response from Claude.',
          aiOnline: true,
        );
      }

      // Extract text blocks from response
      final textBlocks = content
          .where((c) => c['type'] == 'text')
          .map((c) => c['text'] as String)
          .join('\n');

      return ChatResponse(
        text: textBlocks,
        aiOnline: true,
      );
    } catch (e) {
      return ChatResponse(
        text: 'Failed to reach Claude API: $e',
        aiOnline: false,
      );
    }
  }

  /// Stream a chat response from Claude API, yielding text chunks via SSE.
  Stream<String> streamChat(
    String query,
    List<ChatMessage> history,
    String vaultContext,
  ) async* {
    if (!isConfigured) {
      yield 'Claude API key not configured. Go to Settings to add your API key.';
      return;
    }

    try {
      final messages = <Map<String, String>>[
        ...history.map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.text,
            }),
        {'role': 'user', 'content': query},
      ];

      final systemPrompt =
          '${AiService.systemPrompt}\n\n'
          'IMPORTANT: You are running as a CLOUD model. Secrets have been automatically '
          'locked for security. You can access notes, ideas, and documents but NOT secrets. '
          'If the user asks about secrets, remind them to switch to a local Ollama model '
          'to access secrets securely.\n\n'
          '$vaultContext';

      final body = {
        'model': _model,
        'max_tokens': 4096,
        'stream': true,
        'system': systemPrompt,
        'messages': messages,
      };

      final request = http.Request('POST', Uri.parse(_apiUrl));
      request.headers.addAll(_headers());
      request.body = jsonEncode(body);

      final response = await http.Client().send(request).timeout(
        const Duration(seconds: 120),
      );

      if (response.statusCode != 200) {
        // Read full body for error
        final errorBody = await response.stream.bytesToString();
        try {
          final json = jsonDecode(errorBody) as Map<String, dynamic>;
          final error = json['error'] as Map<String, dynamic>?;
          yield 'Claude API error: ${error?['message'] ?? 'HTTP ${response.statusCode}'}';
        } catch (_) {
          yield 'Claude API error: HTTP ${response.statusCode}';
        }
        return;
      }

      // Parse SSE stream — Claude sends events like:
      // event: content_block_delta
      // data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data == '[DONE]') return;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final type = json['type'] as String?;
            if (type == 'content_block_delta') {
              final delta = json['delta'] as Map<String, dynamic>?;
              if (delta?['type'] == 'text_delta') {
                final text = delta!['text'] as String? ?? '';
                if (text.isNotEmpty) yield text;
              }
            } else if (type == 'error') {
              final error = json['error'] as Map<String, dynamic>?;
              yield '\n[Error: ${error?['message'] ?? 'Unknown error'}]';
              return;
            }
          } catch (_) {
            // Skip malformed SSE lines
          }
        }
      }
    } catch (e) {
      yield '[Error: Failed to reach Claude API: $e]';
    }
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': _apiVersion,
      };

  String _parseError(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      return error?['message'] as String? ?? 'HTTP ${response.statusCode}';
    } catch (_) {
      return 'HTTP ${response.statusCode}';
    }
  }
}
