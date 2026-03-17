import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../models/vault_entry.dart';
import '../services/api_server.dart';
import 'notes_provider.dart';
import 'vault_provider.dart';

final apiServerProvider =
    StateNotifierProvider<ApiServerNotifier, ApiServerState>((ref) {
  return ApiServerNotifier(ref);
});

class ApiServerState {
  final bool enabled;
  final bool isRunning;
  final int port;
  final String? error;
  final String? apiKey;

  const ApiServerState({
    this.enabled = false,
    this.isRunning = false,
    this.port = 8484,
    this.error,
    this.apiKey,
  });

  ApiServerState copyWith({
    bool? enabled,
    bool? isRunning,
    int? port,
    String? Function()? error,
    String? Function()? apiKey,
  }) {
    return ApiServerState(
      enabled: enabled ?? this.enabled,
      isRunning: isRunning ?? this.isRunning,
      port: port ?? this.port,
      error: error != null ? error() : this.error,
      apiKey: apiKey != null ? apiKey() : this.apiKey,
    );
  }
}

class ApiServerNotifier extends StateNotifier<ApiServerState> {
  final Ref _ref;
  final VaultApiServer _server = VaultApiServer();

  ApiServerNotifier(this._ref) : super(const ApiServerState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('api_server_enabled') ?? false;
    final port = prefs.getInt('api_server_port') ?? 8484;
    final apiKey = prefs.getString('api_server_key');

    state = state.copyWith(
      enabled: enabled,
      port: port,
      apiKey: () => apiKey,
    );

    if (enabled && apiKey != null) {
      await _startServer(port, apiKey);
    } else if (enabled && apiKey == null) {
      // Was enabled but key got lost — generate a new one
      final newKey = _generateApiKey();
      await prefs.setString('api_server_key', newKey);
      state = state.copyWith(apiKey: () => newKey);
      await _startServer(port, newKey);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('api_server_enabled', enabled);

    if (enabled) {
      // Generate a fresh API key
      final newKey = _generateApiKey();
      await prefs.setString('api_server_key', newKey);
      state = state.copyWith(
        enabled: true,
        apiKey: () => newKey,
        error: () => null,
      );
      await _startServer(state.port, newKey);
    } else {
      // Drop the API key
      await prefs.remove('api_server_key');
      state = state.copyWith(
        enabled: false,
        apiKey: () => null,
        error: () => null,
      );
      await _stopServer();
    }
  }

  Future<void> setPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('api_server_port', port);

    final wasRunning = state.isRunning;
    if (wasRunning) {
      await _stopServer();
    }

    state = state.copyWith(port: port, error: () => null);

    if (wasRunning || state.enabled) {
      await _startServer(port, state.apiKey);
    }
  }

  String _generateApiKey() {
    // Generate a URL-safe key from two UUIDs (no dashes) for good entropy
    const uuid = Uuid();
    final part1 = uuid.v4().replaceAll('-', '');
    final part2 = uuid.v4().replaceAll('-', '').substring(0, 16);
    return 'avk_$part1$part2';
  }

  Future<void> _startServer(int port, String? apiKey) async {
    try {
      _server.setApiKey(apiKey);
      _server.setDataSources(
        getEntries: () {
          final entriesAsync = _ref.read(vaultEntriesProvider);
          return entriesAsync.whenOrNull<List<VaultEntry>>(
                data: (data) => data,
              ) ??
              [];
        },
        getNotes: () {
          final notesAsync = _ref.read(notesProvider);
          return notesAsync.whenOrNull<List<Note>>(
                data: (data) => data,
              ) ??
              [];
        },
      );

      await _server.start(port: port);
      state = state.copyWith(isRunning: true, error: () => null);
    } catch (e) {
      state = state.copyWith(
        isRunning: false,
        error: () => e.toString(),
      );
    }
  }

  Future<void> _stopServer() async {
    _server.setApiKey(null);
    await _server.stop();
    state = state.copyWith(isRunning: false);
  }

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }
}
