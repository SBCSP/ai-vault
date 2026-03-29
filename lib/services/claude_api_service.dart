import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_service.dart';

/// Service for calling the Claude (Anthropic) API.
///
/// This is a cloud-based LLM — secrets are NEVER sent to this service.
/// The secrets lock is automatically engaged when this provider is active.
class ClaudeApiService {
  static const _apiUrl = 'https://api.anthropic.com/v1/messages';
  static const _apiVersion = '2023-06-01';
  static const _defaultModel = 'claude-sonnet-4-20250514';

  String _apiKey;
  String _model;

  ClaudeApiService({
    String apiKey = '',
    String model = _defaultModel,
  })  : _apiKey = apiKey,
        _model = model;

  String get apiKey => _apiKey;
  String get model => _model;
  bool get isConfigured => _apiKey.isNotEmpty;

  void updateApiKey(String key) => _apiKey = key;
  void updateModel(String model) => _model = model;

  /// Available Claude models for selection.
  static const availableModels = [
    ('claude-sonnet-4-20250514', 'Claude Sonnet 4', 'Fast & capable'),
    ('claude-opus-4-20250514', 'Claude Opus 4', 'Most intelligent'),
    ('claude-haiku-4-20250514', 'Claude Haiku 4', 'Fastest & most compact'),
  ];

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
