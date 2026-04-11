import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/lance_db_service.dart';

// ─── Embedding-dim preference ────────────────────────────────────────────────

/// The embedding dimension must match the model.
/// nomic-embed-text → 768, mxbai-embed-large → 1024, etc.
final embeddingDimProvider =
    StateNotifierProvider<EmbeddingDimNotifier, int>((ref) {
  return EmbeddingDimNotifier();
});

class EmbeddingDimNotifier extends StateNotifier<int> {
  EmbeddingDimNotifier() : super(768) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('lance_embedding_dim') ?? 768;
  }

  Future<void> update(int dim) async {
    state = dim;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lance_embedding_dim', dim);
  }
}

// ─── VectorDB state ──────────────────────────────────────────────────────────

class VectorDbState {
  final bool isInitialized;
  final bool isInitializing;
  final String? error;
  final VectorDbStats? stats;
  final bool isLoadingStats;
  final bool isIndexing;
  final String? indexError;

  const VectorDbState({
    this.isInitialized = false,
    this.isInitializing = false,
    this.error,
    this.stats,
    this.isLoadingStats = false,
    this.isIndexing = false,
    this.indexError,
  });

  VectorDbState copyWith({
    bool? isInitialized,
    bool? isInitializing,
    String? Function()? error,
    VectorDbStats? Function()? stats,
    bool? isLoadingStats,
    bool? isIndexing,
    String? Function()? indexError,
  }) {
    return VectorDbState(
      isInitialized: isInitialized ?? this.isInitialized,
      isInitializing: isInitializing ?? this.isInitializing,
      error: error != null ? error() : this.error,
      stats: stats != null ? stats() : this.stats,
      isLoadingStats: isLoadingStats ?? this.isLoadingStats,
      isIndexing: isIndexing ?? this.isIndexing,
      indexError: indexError != null ? indexError() : this.indexError,
    );
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final vectorDbProvider =
    StateNotifierProvider<VectorDbNotifier, VectorDbState>((ref) {
  final dim = ref.watch(embeddingDimProvider);
  return VectorDbNotifier(embeddingDim: dim);
});

class VectorDbNotifier extends StateNotifier<VectorDbState> {
  final int embeddingDim;

  VectorDbNotifier({required this.embeddingDim})
      : super(const VectorDbState()) {
    _init();
  }

  Future<void> _init() async {
    if (state.isInitializing) return;
    state = state.copyWith(isInitializing: true, error: () => null);

    final ok = await LanceDbService.initialize(embeddingDim: embeddingDim);

    if (ok) {
      state = state.copyWith(isInitialized: true, isInitializing: false);
      await refreshStats();
    } else {
      state = state.copyWith(
        isInitialized: false,
        isInitializing: false,
        error: () =>
            'Rust bridge not compiled.\n\nRun: dart run flutter_rust_bridge_codegen generate',
      );
    }
  }

  /// Re-attempt initialisation (useful after the user installs the bridge).
  Future<void> reinitialize() => _init();

  Future<void> refreshStats() async {
    if (!state.isInitialized) return;
    state = state.copyWith(isLoadingStats: true);
    try {
      final stats = await LanceDbService.getStats();
      state = state.copyWith(
        isLoadingStats: false,
        stats: () => stats,
      );
    } catch (e) {
      state = state.copyWith(isLoadingStats: false);
    }
  }

  Future<void> createIndex() async {
    if (!state.isInitialized) return;
    state = state.copyWith(isIndexing: true, indexError: () => null);
    try {
      await LanceDbService.createVectorIndex();
      state = state.copyWith(isIndexing: false);
      await refreshStats();
    } catch (e) {
      state = state.copyWith(
        isIndexing: false,
        indexError: () => e.toString(),
      );
    }
  }

  Future<void> deleteAll() async {
    if (!state.isInitialized) return;
    await LanceDbService.deleteAll();
    await refreshStats();
  }
}
