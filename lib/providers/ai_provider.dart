import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vault_entry.dart';
import '../services/ai_service.dart';
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

final aiSearchProvider =
    StateNotifierProvider<AiSearchNotifier, AiSearchState>((ref) {
  return AiSearchNotifier(ref);
});

class AiSearchState {
  final bool isSearching;
  final AiSearchResult? result;
  final String? error;

  const AiSearchState({
    this.isSearching = false,
    this.result,
    this.error,
  });
}

class AiSearchNotifier extends StateNotifier<AiSearchState> {
  final Ref _ref;

  AiSearchNotifier(this._ref) : super(const AiSearchState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const AiSearchState();
      return;
    }

    state = const AiSearchState(isSearching: true);

    try {
      final aiService = _ref.read(aiServiceProvider);
      final entriesAsync = _ref.read(vaultEntriesProvider);

      final entries = entriesAsync.whenOrNull<List<VaultEntry>>(
            data: (data) => data,
          ) ??
          [];

      final result = await aiService.searchVault(query, entries);
      state = AiSearchState(result: result);
    } catch (e) {
      state = AiSearchState(error: e.toString());
    }
  }

  void clear() {
    state = const AiSearchState();
  }
}
