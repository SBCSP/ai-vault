import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../src/rust/api.dart';

export '../src/rust/api.dart'
    show SimilarityResult, SourceHashEntry, VectorDbStats, TypeCount, EmbeddingRow;

/// Dart façade over the flutter_rust_bridge LanceDB API.
///
/// Before codegen is run, every call throws [UnsupportedError].
/// [LanceDbService.initialize] catches that and returns false,
/// leaving the app in SQLite-fallback mode.
///
/// After running `dart run flutter_rust_bridge_codegen generate`
/// and rebuilding, the real Rust implementations take over.
class LanceDbService {
  LanceDbService._();

  static bool _initialized = false;
  static int _embeddingDim = 768;

  static bool get isAvailable => _initialized;

  // ── Lifecycle ─────────────────────────────────────────────

  /// Initialise LanceDB.  Safe to call multiple times; subsequent calls
  /// are no-ops if already initialised with the same dim.
  ///
  /// Returns true when the Rust bridge is compiled and init succeeds.
  /// Last initialization error, exposed so the UI can show a specific message.
  static String? lastError;

  static Future<bool> initialize({int embeddingDim = 768}) async {
    if (_initialized) return true;
    try {
      final appDir = await getApplicationSupportDirectory();
      final dbPath = p.join(appDir.path, 'lance_vectors');
      _embeddingDim = embeddingDim;
      await initLanceDb(dbPath: dbPath, embeddingDim: embeddingDim);
      _initialized = true;
      lastError = null;
      return true;
    } on UnsupportedError catch (e) {
      // FRB stub — app was not built with the Rust library
      _initialized = false;
      lastError = 'UnsupportedError: $e';
      return false;
    } catch (e) {
      _initialized = false;
      lastError = e.toString();
      return false;
    }
  }

  // ── Write ──────────────────────────────────────────────────

  /// Insert or replace an embedding.  Vector must match the initialised dim.
  static Future<void> upsertEmbedding({
    required String sourceId,
    required String sourceType,
    required String modelName,
    required String contentHash,
    required List<double> vector,
  }) async {
    await lanceUpsertEmbedding(
      sourceId: sourceId,
      sourceType: sourceType,
      modelName: modelName,
      contentHash: contentHash,
      vector: Float32List.fromList(vector),
    );
  }

  static Future<void> deleteBySource(String sourceId) async {
    await lanceDeleteBySource(sourceId: sourceId);
  }

  static Future<void> deleteAll() async {
    await lanceDeleteAll();
  }

  // ── Read / Search ─────────────────────────────────────────

  /// Check if a source item is already indexed (and with which hash/model).
  /// Returns null if not found.
  static Future<SourceHashEntry?> getSourceHash(String sourceId) async {
    return lanceGetSourceHash(sourceId: sourceId);
  }

  /// Bulk hash lookup — used by reindexAll to detect what changed.
  static Future<List<SourceHashEntry>> getAllHashes({
    String sourceTypeFilter = '',
  }) async {
    return lanceGetAllHashes(sourceTypeFilter: sourceTypeFilter);
  }

  /// ANN cosine-similarity search.
  ///
  /// [topK]          — max results
  /// [filterTypes]   — restrict to these source_type values (empty = all)
  ///
  /// Results are ordered by similarity descending.
  static Future<List<SimilarityResult>> searchSimilar({
    required List<double> queryVector,
    int topK = 10,
    List<String> filterTypes = const [],
  }) async {
    return lanceSearchSimilar(
      queryVector: Float32List.fromList(queryVector),
      topK: topK,
      filterTypes: filterTypes,
    );
  }

  // ── Admin ─────────────────────────────────────────────────

  static Future<VectorDbStats> getStats() async {
    return lanceGetStats();
  }

  /// Build an HNSW/IVF-PQ index.  Requires ≥ 256 embeddings.
  /// Throws if count is too low — caller should show a user-facing message.
  static Future<void> createVectorIndex() async {
    await lanceCreateVectorIndex();
  }

  // ── Collections / Browser ────────────────────────────────

  /// Return row counts grouped by source_type.
  static Future<List<TypeCount>> getTypeCounts() async {
    return lanceGetTypeCounts();
  }

  /// Return a page of embedding rows (no vector bytes) for the Browser tab.
  /// [sourceTypeFilter] — pass empty string for all types.
  static Future<List<EmbeddingRow>> getRowsPage({
    String sourceTypeFilter = '',
    int offset = 0,
    int limit = 50,
  }) async {
    return lanceGetRowsPage(
      sourceTypeFilter: sourceTypeFilter,
      offset: offset,
      limit: limit,
    );
  }

  /// Delete all embeddings whose source_type matches [sourceType].
  static Future<void> deleteByType(String sourceType) async {
    await lanceDeleteByType(sourceType: sourceType);
  }

  // ── Helpers ───────────────────────────────────────────────

  static int get embeddingDim => _embeddingDim;
}
