import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/document.dart' as model;
import '../models/note.dart' as model;
import '../models/vault_entry.dart' as model;
import '../services/document_service.dart';
import '../services/embedding_service.dart';
import 'ai_provider.dart';
import 'documents_provider.dart';
import 'notes_provider.dart';
import 'vault_provider.dart';

// --- Embedding Model Provider ---
// Persists the active embedding model name to SharedPreferences.

final embeddingModelProvider =
    StateNotifierProvider<EmbeddingModelNotifier, String>((ref) {
  return EmbeddingModelNotifier();
});

class EmbeddingModelNotifier extends StateNotifier<String> {
  EmbeddingModelNotifier() : super('nomic-embed-text:latest') {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('embedding_model');
    if (saved != null && saved.isNotEmpty) {
      state = saved;
    }
  }

  Future<void> updateModel(String model) async {
    state = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('embedding_model', model);
  }
}

// --- Embedding Service Provider ---
// Creates an EmbeddingService from the current server URL and embedding model.

final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  final aiService = ref.watch(aiServiceProvider);
  final embeddingModel = ref.watch(embeddingModelProvider);
  return EmbeddingService(
    serverUrl: aiService.serverUrl,
    model: embeddingModel,
  );
});

// --- Embedding Index Provider ---
// Manages embedding indexing state and operations.

final embeddingIndexProvider =
    StateNotifierProvider<EmbeddingIndexNotifier, EmbeddingIndexState>((ref) {
  return EmbeddingIndexNotifier(ref);
});

class EmbeddingIndexState {
  final bool isIndexing;
  final int totalItems;
  final int processedItems;
  final String? error;
  final int indexedCount;

  const EmbeddingIndexState({
    this.isIndexing = false,
    this.totalItems = 0,
    this.processedItems = 0,
    this.error,
    this.indexedCount = 0,
  });

  EmbeddingIndexState copyWith({
    bool? isIndexing,
    int? totalItems,
    int? processedItems,
    String? Function()? error,
    int? indexedCount,
  }) {
    return EmbeddingIndexState(
      isIndexing: isIndexing ?? this.isIndexing,
      totalItems: totalItems ?? this.totalItems,
      processedItems: processedItems ?? this.processedItems,
      error: error != null ? error() : this.error,
      indexedCount: indexedCount ?? this.indexedCount,
    );
  }
}

class EmbeddingIndexNotifier extends StateNotifier<EmbeddingIndexState> {
  final Ref _ref;
  static const _uuid = Uuid();

  EmbeddingIndexNotifier(this._ref) : super(const EmbeddingIndexState()) {
    refreshStats();
  }

  AppDatabase get _db => _ref.read(databaseProvider);
  EmbeddingService get _service => _ref.read(embeddingServiceProvider);
  String get _modelName => _ref.read(embeddingModelProvider);

  Future<void> refreshStats() async {
    final count = await _db.countEmbeddings();
    if (mounted) {
      state = state.copyWith(indexedCount: count);
    }
  }

  /// Index a single vault entry. Skips if content hash is unchanged.
  Future<void> indexEntry(model.VaultEntry entry) async {
    final text = EmbeddingService.buildEntryText(entry);
    final hash = EmbeddingService.computeContentHash(text);

    // Check if already indexed with same hash
    final existing = await _db.getEmbeddingBySourceId(entry.id);
    if (existing != null &&
        existing.contentHash == hash &&
        existing.modelName == _modelName) {
      return;
    }

    final vector = await _service.generateEmbedding(text);
    if (vector == null) return;

    await _db.upsertEmbedding(EmbeddingsCompanion(
      id: Value(existing?.id ?? _uuid.v4()),
      sourceId: Value(entry.id),
      sourceType: const Value('vault_entry'),
      embedding: Value(jsonEncode(vector)),
      modelName: Value(_modelName),
      contentHash: Value(hash),
      createdAt: Value(DateTime.now()),
    ));

    await refreshStats();
  }

  /// Index a single note. Skips if content hash is unchanged.
  Future<void> indexNote(model.Note note) async {
    final text = EmbeddingService.buildNoteText(note);
    final hash = EmbeddingService.computeContentHash(text);

    final existing = await _db.getEmbeddingBySourceId(note.id);
    if (existing != null &&
        existing.contentHash == hash &&
        existing.modelName == _modelName) {
      return;
    }

    final vector = await _service.generateEmbedding(text);
    if (vector == null) return;

    await _db.upsertEmbedding(EmbeddingsCompanion(
      id: Value(existing?.id ?? _uuid.v4()),
      sourceId: Value(note.id),
      sourceType: const Value('note'),
      embedding: Value(jsonEncode(vector)),
      modelName: Value(_modelName),
      contentHash: Value(hash),
      createdAt: Value(DateTime.now()),
    ));

    await refreshStats();
  }

  /// Remove embedding when a vault entry is deleted.
  Future<void> removeEntry(String id) async {
    await _db.deleteEmbeddingBySourceId(id);
    await refreshStats();
  }

  /// Remove embedding when a note is deleted.
  Future<void> removeNote(String id) async {
    await _db.deleteEmbeddingBySourceId(id);
    await refreshStats();
  }

  /// Index all chunks for a document. Reads file, chunks it, embeds each.
  Future<void> indexDocument(model.Document doc) async {
    final content = await DocumentService.readFileContent(doc.filePath);
    if (content == null) return;

    final fileHash = EmbeddingService.computeContentHash(content);

    // Skip if content hasn't changed
    if (doc.contentHash == fileHash && doc.lastIndexedAt != null) return;

    // Delete existing chunks and their embeddings
    await removeDocument(doc.id);

    // Chunk the content
    final chunks = DocumentService.chunkText(content);

    for (var i = 0; i < chunks.length; i++) {
      if (!mounted) return;

      final chunkId = _uuid.v4();
      final chunkHash = EmbeddingService.computeContentHash(chunks[i]);

      // Store chunk in DB
      await _db.insertDocumentChunk(DocumentChunksCompanion.insert(
        id: chunkId,
        documentId: doc.id,
        chunkIndex: i,
        content: chunks[i],
        contentHash: Value(chunkHash),
        createdAt: DateTime.now(),
      ));

      // Generate and store embedding with document title prefix
      final textForEmbedding =
          EmbeddingService.buildChunkText(doc.title, chunks[i]);
      final vector = await _service.generateEmbedding(textForEmbedding);

      if (vector != null) {
        await _db.upsertEmbedding(EmbeddingsCompanion(
          id: Value(_uuid.v4()),
          sourceId: Value(chunkId),
          sourceType: const Value('document_chunk'),
          embedding: Value(jsonEncode(vector)),
          modelName: Value(_modelName),
          contentHash: Value(chunkHash),
          createdAt: Value(DateTime.now()),
        ));
      }
    }

    // Update document record with new hash and chunk count
    await _db.updateDocument(DocumentsCompanion(
      id: Value(doc.id),
      chunkCount: Value(chunks.length),
      contentHash: Value(fileHash),
      lastIndexedAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ));

    await refreshStats();
  }

  /// Remove all embeddings and chunks for a document.
  Future<void> removeDocument(String documentId) async {
    final chunks = await _db.getChunksByDocumentId(documentId);
    for (final chunk in chunks) {
      await _db.deleteEmbeddingBySourceId(chunk.id);
    }
    await _db.deleteChunksByDocumentId(documentId);
    await refreshStats();
  }

  /// Re-index all entries, notes, and documents from scratch.
  Future<void> reindexAll() async {
    if (state.isIndexing) return;

    final entriesAsync = _ref.read(vaultEntriesProvider);
    final entries = entriesAsync.whenOrNull<List<model.VaultEntry>>(
          data: (data) => data,
        ) ??
        [];

    final notesAsync = _ref.read(notesProvider);
    final notesList = notesAsync.whenOrNull<List<model.Note>>(
          data: (data) => data,
        ) ??
        [];

    final docsAsync = _ref.read(documentsProvider);
    final docsList = docsAsync.whenOrNull<List<model.Document>>(
          data: (data) => data,
        ) ??
        [];

    final total = entries.length + notesList.length + docsList.length;
    state = EmbeddingIndexState(
      isIndexing: true,
      totalItems: total,
      processedItems: 0,
      indexedCount: state.indexedCount,
    );

    // Clear all existing embeddings and document chunks
    await _db.deleteAllEmbeddings();
    for (final doc in docsList) {
      await _db.deleteChunksByDocumentId(doc.id);
    }

    var processed = 0;

    for (final entry in entries) {
      if (!mounted) return;
      final text = EmbeddingService.buildEntryText(entry);
      final hash = EmbeddingService.computeContentHash(text);
      final vector = await _service.generateEmbedding(text);

      if (vector != null) {
        await _db.upsertEmbedding(EmbeddingsCompanion(
          id: Value(_uuid.v4()),
          sourceId: Value(entry.id),
          sourceType: const Value('vault_entry'),
          embedding: Value(jsonEncode(vector)),
          modelName: Value(_modelName),
          contentHash: Value(hash),
          createdAt: Value(DateTime.now()),
        ));
      }

      processed++;
      if (mounted) {
        state = state.copyWith(processedItems: processed);
      }
    }

    for (final note in notesList) {
      if (!mounted) return;
      final text = EmbeddingService.buildNoteText(note);
      final hash = EmbeddingService.computeContentHash(text);
      final vector = await _service.generateEmbedding(text);

      if (vector != null) {
        await _db.upsertEmbedding(EmbeddingsCompanion(
          id: Value(_uuid.v4()),
          sourceId: Value(note.id),
          sourceType: const Value('note'),
          embedding: Value(jsonEncode(vector)),
          modelName: Value(_modelName),
          contentHash: Value(hash),
          createdAt: Value(DateTime.now()),
        ));
      }

      processed++;
      if (mounted) {
        state = state.copyWith(processedItems: processed);
      }
    }

    // Re-index documents (each document generates multiple chunk embeddings)
    for (final doc in docsList) {
      if (!mounted) return;

      final content = await DocumentService.readFileContent(doc.filePath);
      if (content != null) {
        final fileHash = EmbeddingService.computeContentHash(content);
        final chunks = DocumentService.chunkText(content);

        for (var i = 0; i < chunks.length; i++) {
          if (!mounted) return;

          final chunkId = _uuid.v4();
          final chunkHash = EmbeddingService.computeContentHash(chunks[i]);

          await _db.insertDocumentChunk(DocumentChunksCompanion.insert(
            id: chunkId,
            documentId: doc.id,
            chunkIndex: i,
            content: chunks[i],
            contentHash: Value(chunkHash),
            createdAt: DateTime.now(),
          ));

          final textForEmbedding =
              EmbeddingService.buildChunkText(doc.title, chunks[i]);
          final vector = await _service.generateEmbedding(textForEmbedding);

          if (vector != null) {
            await _db.upsertEmbedding(EmbeddingsCompanion(
              id: Value(_uuid.v4()),
              sourceId: Value(chunkId),
              sourceType: const Value('document_chunk'),
              embedding: Value(jsonEncode(vector)),
              modelName: Value(_modelName),
              contentHash: Value(chunkHash),
              createdAt: Value(DateTime.now()),
            ));
          }
        }

        // Update document record
        await _db.updateDocument(DocumentsCompanion(
          id: Value(doc.id),
          chunkCount: Value(chunks.length),
          contentHash: Value(fileHash),
          lastIndexedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
      }

      processed++;
      if (mounted) {
        state = state.copyWith(processedItems: processed);
      }
    }

    if (mounted) {
      final count = await _db.countEmbeddings();
      state = EmbeddingIndexState(
        isIndexing: false,
        totalItems: total,
        processedItems: total,
        indexedCount: count,
      );
    }
  }
}
