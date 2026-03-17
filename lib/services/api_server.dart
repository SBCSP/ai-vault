import 'dart:convert';
import 'dart:io';

import '../models/note.dart';
import '../models/vault_entry.dart';

/// Local HTTP API server that exposes vault secrets and notes to
/// applications running on the same machine.
///
/// Endpoints:
///   GET /api/secrets             — List all secrets (no passwords)
///   GET /api/secrets/:id         — Get a secret by ID (includes password)
///   GET /api/secrets/lookup?title=... — Lookup by title (includes password)
///   GET /api/notes               — List all notes
///   GET /api/notes/:id           — Get a note by ID
///   GET /api/health              — Health check
class VaultApiServer {
  HttpServer? _server;
  int _port;
  String? _apiKey;

  /// Callbacks to fetch current decrypted data from providers.
  List<VaultEntry> Function()? _getEntries;
  List<Note> Function()? _getNotes;

  VaultApiServer({int port = 8484}) : _port = port;

  int get port => _port;
  bool get isRunning => _server != null;

  void setApiKey(String? key) => _apiKey = key;

  void setDataSources({
    required List<VaultEntry> Function() getEntries,
    required List<Note> Function() getNotes,
  }) {
    _getEntries = getEntries;
    _getNotes = getNotes;
  }

  Future<void> start({int? port}) async {
    if (_server != null) return; // Already running
    if (port != null) _port = port;

    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _port,
    );

    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void _handleRequest(HttpRequest request) async {
    // CORS headers for local dev tools
    request.response.headers
      ..set('Content-Type', 'application/json')
      ..set('Access-Control-Allow-Origin', 'http://localhost:*')
      ..set('X-Powered-By', 'AI Vault');

    if (request.method == 'OPTIONS') {
      request.response.headers
        ..set('Access-Control-Allow-Methods', 'GET, OPTIONS')
        ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }

    if (request.method != 'GET') {
      _sendError(request, 405, 'Method not allowed. Only GET is supported.');
      return;
    }

    // API key authentication
    if (_apiKey != null) {
      final authHeader = request.headers.value('authorization');
      final queryKey = request.uri.queryParameters['api_key'];
      final providedKey = _extractBearerToken(authHeader) ?? queryKey;

      if (providedKey != _apiKey) {
        _sendError(request, 401, 'Unauthorized. Provide a valid API key via '
            'Authorization: Bearer <key> header or ?api_key=<key> query param.');
        return;
      }
    }

    final path = request.uri.path;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();

    try {
      // Route: /api/...
      if (segments.length < 2 || segments[0] != 'api') {
        _sendError(request, 404, 'Not found. Try /api/secrets or /api/notes');
        return;
      }

      switch (segments[1]) {
        case 'health':
          _sendJson(request, {'status': 'ok', 'vault': 'AI Vault'});
          return;
        case 'secrets':
          _handleSecrets(request, segments);
          return;
        case 'notes':
          _handleNotes(request, segments);
          return;
        default:
          _sendError(request, 404, 'Unknown endpoint: ${segments[1]}');
      }
    } catch (e) {
      _sendError(request, 500, 'Internal server error');
    }
  }

  void _handleSecrets(HttpRequest request, List<String> segments) {
    final entries = _getEntries?.call() ?? [];

    // GET /api/secrets
    if (segments.length == 2) {
      // Check for ?title= query parameter (lookup)
      final titleQuery = request.uri.queryParameters['title'];
      if (titleQuery != null) {
        return _handleSecretLookup(request, entries, titleQuery);
      }

      // List all — omit passwords for safety
      final list = entries.map((e) => _secretSummary(e)).toList();
      _sendJson(request, {'count': list.length, 'secrets': list});
      return;
    }

    // GET /api/secrets/:id
    if (segments.length == 3) {
      final id = segments[2];
      final entry = entries.where((e) => e.id == id).firstOrNull;
      if (entry == null) {
        _sendError(request, 404, 'Secret not found');
        return;
      }
      _sendJson(request, _secretFull(entry));
      return;
    }

    _sendError(request, 404, 'Not found');
  }

  void _handleSecretLookup(
    HttpRequest request,
    List<VaultEntry> entries,
    String titleQuery,
  ) {
    final queryLower = titleQuery.toLowerCase();
    final matches = entries
        .where((e) => e.title.toLowerCase().contains(queryLower))
        .toList();

    if (matches.isEmpty) {
      _sendError(request, 404, 'No secrets matching "$titleQuery"');
      return;
    }

    if (matches.length == 1) {
      _sendJson(request, _secretFull(matches.first));
      return;
    }

    // Multiple matches — return full details for all
    _sendJson(request, {
      'count': matches.length,
      'secrets': matches.map((e) => _secretFull(e)).toList(),
    });
  }

  void _handleNotes(HttpRequest request, List<String> segments) {
    final notes = _getNotes?.call() ?? [];

    // GET /api/notes
    if (segments.length == 2) {
      final list = notes.map((n) => n.toMap()).toList();
      _sendJson(request, {'count': list.length, 'notes': list});
      return;
    }

    // GET /api/notes/:id
    if (segments.length == 3) {
      final id = segments[2];
      final note = notes.where((n) => n.id == id).firstOrNull;
      if (note == null) {
        _sendError(request, 404, 'Note not found');
        return;
      }
      _sendJson(request, note.toMap());
      return;
    }

    _sendError(request, 404, 'Not found');
  }

  /// Summary without password — used for listing.
  Map<String, dynamic> _secretSummary(VaultEntry e) {
    return {
      'id': e.id,
      'title': e.title,
      'username': e.username,
      'url': e.url,
      'category': e.category,
      'tags': e.tags,
      'createdAt': e.createdAt.toIso8601String(),
      'updatedAt': e.updatedAt.toIso8601String(),
      'expiresAt': e.expiresAt?.toIso8601String(),
      'isExpired': e.isExpired,
    };
  }

  /// Full entry with password — used for single lookups.
  Map<String, dynamic> _secretFull(VaultEntry e) {
    return e.toMap();
  }

  void _sendJson(HttpRequest request, Object data) {
    request.response
      ..statusCode = 200
      ..write(jsonEncode(data))
      ..close();
  }

  void _sendError(HttpRequest request, int code, String message) {
    request.response
      ..statusCode = code
      ..write(jsonEncode({'error': message}))
      ..close();
  }

  String? _extractBearerToken(String? header) {
    if (header == null) return null;
    if (header.startsWith('Bearer ')) return header.substring(7).trim();
    return null;
  }
}
