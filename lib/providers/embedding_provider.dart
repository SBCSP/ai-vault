import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/chat_session.dart' as model;
import '../models/document.dart' as model;
import '../models/idea.dart' as model;
import '../models/note.dart' as model;
import '../models/vault_entry.dart' as model;
import '../services/document_service.dart';
import '../services/embedding_service.dart';
import '../services/lance_db_service.dart';
import 'ai_provider.dart';
import 'documents_provider.dart';
import 'ideas_provider.dart';
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
    try {
      final stats = await LanceDbService.getStats();
      if (mounted) {
        state = state.copyWith(indexedCount: stats.totalEmbeddings.toInt());
      }
    } catch (_) {
      // LanceDB unavailable — count stays at current value
    }
  }

  // ── LanceDB helpers ─────────────────────────────────────────────────────

  /// Returns true if this sourceId is already indexed with the same hash+model.
  Future<bool> _isAlreadyIndexed(String sourceId, String hash) async {
    try {
      final entry = await LanceDbService.getSourceHash(sourceId);
      return entry != null &&
          entry.contentHash == hash &&
          entry.modelName == _modelName;
    } catch (_) {
      return false;
    }
  }

  /// Write vector to LanceDB (exclusive store).
  Future<void> _upsertVector({
    required String sourceId,
    required String sourceType,
    required String hash,
    required List<double> vector,
  }) async {
    await LanceDbService.upsertEmbedding(
      sourceId: sourceId,
      sourceType: sourceType,
      modelName: _modelName,
      contentHash: hash,
      vector: vector,
    );
    await refreshStats();
  }

  // ── RAG search (ANN via LanceDB) ────────────────────────────────────────

  /// Semantic similarity search over all indexed embeddings.
  /// Returns source IDs+types sorted by score descending.
  Future<List<({String sourceId, String sourceType, double score})>> ragSearch(
    List<double> queryVector, {
    int topK = 10,
    double threshold = 0.3,
  }) async {
    try {
      final results = await LanceDbService.searchSimilar(
        queryVector: queryVector,
        topK: topK,
      );
      return results
          .where((r) => r.similarity >= threshold)
          .map((r) => (
                sourceId: r.sourceId,
                sourceType: r.sourceType,
                score: r.similarity,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Index a single vault entry. Skips if content hash is unchanged.
  Future<void> indexEntry(model.VaultEntry entry) async {
    final text = EmbeddingService.buildEntryText(entry);
    final hash = EmbeddingService.computeContentHash(text);

    if (await _isAlreadyIndexed(entry.id, hash)) return;

    final vector = await _service.generateEmbedding(text);
    if (vector == null) return;

    await _upsertVector(
      sourceId: entry.id,
      sourceType: 'vault_entry',
      hash: hash,
      vector: vector,
    );
  }

  /// Index a single note. Skips if content hash is unchanged.
  Future<void> indexNote(model.Note note) async {
    final text = EmbeddingService.buildNoteText(note);
    final hash = EmbeddingService.computeContentHash(text);

    if (await _isAlreadyIndexed(note.id, hash)) return;

    final vector = await _service.generateEmbedding(text);
    if (vector == null) return;

    await _upsertVector(
      sourceId: note.id,
      sourceType: 'note',
      hash: hash,
      vector: vector,
    );
  }

  /// Remove embedding when a vault entry is deleted.
  Future<void> removeEntry(String id) async {
    try { await LanceDbService.deleteBySource(id); } catch (_) {}
    await refreshStats();
  }

  /// Remove embedding when a note is deleted.
  Future<void> removeNote(String id) async {
    try { await LanceDbService.deleteBySource(id); } catch (_) {}
    await refreshStats();
  }

  /// Index a single idea. Skips if content hash is unchanged.
  Future<void> indexIdea(model.Idea idea) async {
    final text = EmbeddingService.buildIdeaText(idea);
    final hash = EmbeddingService.computeContentHash(text);

    if (await _isAlreadyIndexed(idea.id, hash)) return;

    final vector = await _service.generateEmbedding(text);
    if (vector == null) return;

    await _upsertVector(
      sourceId: idea.id,
      sourceType: 'idea',
      hash: hash,
      vector: vector,
    );
  }

  /// Remove embedding when an idea is deleted.
  Future<void> removeIdea(String id) async {
    try { await LanceDbService.deleteBySource(id); } catch (_) {}
    await refreshStats();
  }

  /// Index all chunks for a document. Reads file, chunks it, embeds each.
  /// Throws if the file cannot be read (permission error, missing file, etc.)
  Future<void> indexDocument(model.Document doc) async {
    final content = await DocumentService.readFileContent(doc.filePath);
    if (content == null) {
      throw Exception('File not found: ${doc.filePath}');
    }

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

      // Generate and store embedding
      final textForEmbedding =
          EmbeddingService.buildChunkText(doc.title, chunks[i]);
      final vector = await _service.generateEmbedding(textForEmbedding);

      if (vector != null) {
        await LanceDbService.upsertEmbedding(
          sourceId: chunkId,
          sourceType: 'document_chunk',
          modelName: _modelName,
          contentHash: chunkHash,
          vector: vector,
        );
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
      try { await LanceDbService.deleteBySource(chunk.id); } catch (_) {}
    }
    await _db.deleteChunksByDocumentId(documentId);
    await refreshStats();
  }

  /// Index a saved chat session. Single embedding per session.
  Future<void> indexChatSession(model.ChatSession session) async {
    final msgMaps = session.messages
        .map((m) => {'text': m.text, 'isUser': m.isUser})
        .toList();
    final text =
        EmbeddingService.buildChatSessionText(session.title, msgMaps);
    final hash = EmbeddingService.computeContentHash(text);

    if (await _isAlreadyIndexed(session.id, hash)) return;

    final vector = await _service.generateEmbedding(text);
    if (vector == null) return;

    await _upsertVector(
      sourceId: session.id,
      sourceType: 'chat_session',
      hash: hash,
      vector: vector,
    );
  }

  /// Remove embedding for a deleted chat session.
  Future<void> removeChatSession(String id) async {
    try { await LanceDbService.deleteBySource(id); } catch (_) {}
    await refreshStats();
  }

  /// Index a single audit log entry.
  Future<void> indexAuditLog(AuditLog log) async {
    final sourceId = 'audit:${log.id}';
    final text = EmbeddingService.buildAuditLogText(
      log.action,
      log.targetType,
      log.targetName,
      log.details,
      log.createdAt,
    );
    final hash = EmbeddingService.computeContentHash(text);

    if (await _isAlreadyIndexed(sourceId, hash)) return;

    final vector = await _service.generateEmbedding(text);
    if (vector == null) return;

    await _upsertVector(
      sourceId: sourceId,
      sourceType: 'audit_log',
      hash: hash,
      vector: vector,
    );
  }

  /// Batch-index all un-indexed audit logs.
  Future<void> indexAllAuditLogs() async {
    final allLogs = await _db.getAuditLogs(limit: 10000, offset: 0);
    for (final log in allLogs) {
      if (!mounted) return;
      await indexAuditLog(log);
    }
  }

  /// Index all wiki pages from bundled assets.
  /// Uses a version-based hash so pages are only re-indexed when the app updates.
  Future<void> indexWikiPages() async {
    try {
      final jsonStr = await rootBundle.loadString('wiki/wiki.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final wikiVersion = json['version'] as String? ?? '';
      final sections = json['sections'] as List<dynamic>;

      for (final section in sections) {
        final sec = section as Map<String, dynamic>;
        final pages = sec['pages'] as List<dynamic>;
        for (final page in pages) {
          if (!mounted) return;
          final p = page as Map<String, dynamic>;
          final title = p['title'] as String;
          final file = p['file'] as String;
          final sourceId = 'wiki:$file';

          try {
            final content = await rootBundle.loadString('wiki/$file');
            final text = EmbeddingService.buildWikiPageText(title, content);
            // Include version in hash so pages re-index on app update
            final hash = EmbeddingService.computeContentHash('$wikiVersion:$text');

            if (await _isAlreadyIndexed(sourceId, hash)) continue;

            final vector = await _service.generateEmbedding(text);
            if (vector == null) continue;

            await _upsertVector(
              sourceId: sourceId,
              sourceType: 'wiki_page',
              hash: hash,
              vector: vector,
            );
          } catch (_) {
            // Skip pages that fail to load
          }
        }
      }

      await refreshStats();
    } catch (_) {
      // Wiki index not available — skip silently
    }
  }

  /// Re-index all entries, notes, documents, and chat sessions from scratch.
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

    final ideasAsync = _ref.read(ideasProvider);
    final ideaList = ideasAsync.whenOrNull<List<model.Idea>>(
          data: (data) => data,
        ) ??
        [];

    final docsAsync = _ref.read(documentsProvider);
    final docsList = docsAsync.whenOrNull<List<model.Document>>(
          data: (data) => data,
        ) ??
        [];

    // Include indexed chat sessions in re-index
    final indexedSessions = await _db.getIndexedChatSessions();

    // Include audit logs in re-index
    final auditLogs = await _db.getAuditLogs(limit: 10000, offset: 0);

    final total = entries.length + notesList.length + ideaList.length +
        docsList.length + indexedSessions.length + auditLogs.length;
    state = EmbeddingIndexState(
      isIndexing: true,
      totalItems: total,
      processedItems: 0,
      indexedCount: state.indexedCount,
    );

    // Clear all existing embeddings and document chunks
    try { await LanceDbService.deleteAll(); } catch (_) {}
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
        await LanceDbService.upsertEmbedding(
          sourceId: entry.id,
          sourceType: 'vault_entry',
          modelName: _modelName,
          contentHash: hash,
          vector: vector,
        );
      }

      processed++;
      if (mounted) state = state.copyWith(processedItems: processed);
    }

    for (final note in notesList) {
      if (!mounted) return;
      final text = EmbeddingService.buildNoteText(note);
      final hash = EmbeddingService.computeContentHash(text);
      final vector = await _service.generateEmbedding(text);

      if (vector != null) {
        await LanceDbService.upsertEmbedding(
          sourceId: note.id,
          sourceType: 'note',
          modelName: _modelName,
          contentHash: hash,
          vector: vector,
        );
      }

      processed++;
      if (mounted) state = state.copyWith(processedItems: processed);
    }

    for (final idea in ideaList) {
      if (!mounted) return;
      final text = EmbeddingService.buildIdeaText(idea);
      final hash = EmbeddingService.computeContentHash(text);
      final vector = await _service.generateEmbedding(text);

      if (vector != null) {
        await LanceDbService.upsertEmbedding(
          sourceId: idea.id,
          sourceType: 'idea',
          modelName: _modelName,
          contentHash: hash,
          vector: vector,
        );
      }

      processed++;
      if (mounted) state = state.copyWith(processedItems: processed);
    }

    // Re-index documents (each document generates multiple chunk embeddings)
    for (final doc in docsList) {
      if (!mounted) return;

      String? content;
      try {
        content = await DocumentService.readFileContent(doc.filePath);
      } catch (_) {
        // File may be inaccessible — skip this document
      }
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
            await LanceDbService.upsertEmbedding(
              sourceId: chunkId,
              sourceType: 'document_chunk',
              modelName: _modelName,
              contentHash: chunkHash,
              vector: vector,
            );
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
      if (mounted) state = state.copyWith(processedItems: processed);
    }

    // Re-index chat sessions that were previously saved & indexed
    for (final session in indexedSessions) {
      if (!mounted) return;

      final chatSession = model.ChatSession(
        id: session.id,
        title: session.title,
        messages: model.ChatSession.parseMessages(session.messages),
        isIndexed: true,
        createdAt: session.createdAt,
        updatedAt: session.updatedAt,
      );

      final msgMaps = chatSession.messages
          .map((m) => {'text': m.text, 'isUser': m.isUser})
          .toList();
      final text =
          EmbeddingService.buildChatSessionText(chatSession.title, msgMaps);
      final hash = EmbeddingService.computeContentHash(text);
      final vector = await _service.generateEmbedding(text);

      if (vector != null) {
        await LanceDbService.upsertEmbedding(
          sourceId: chatSession.id,
          sourceType: 'chat_session',
          modelName: _modelName,
          contentHash: hash,
          vector: vector,
        );
      }

      processed++;
      if (mounted) state = state.copyWith(processedItems: processed);
    }

    // Re-index audit logs
    for (final log in auditLogs) {
      if (!mounted) return;

      final sourceId = 'audit:${log.id}';
      final text = EmbeddingService.buildAuditLogText(
        log.action,
        log.targetType,
        log.targetName,
        log.details,
        log.createdAt,
      );
      final hash = EmbeddingService.computeContentHash(text);
      final vector = await _service.generateEmbedding(text);

      if (vector != null) {
        await LanceDbService.upsertEmbedding(
          sourceId: sourceId,
          sourceType: 'audit_log',
          modelName: _modelName,
          contentHash: hash,
          vector: vector,
        );
      }

      processed++;
      if (mounted) state = state.copyWith(processedItems: processed);
    }

    if (mounted) {
      int finalCount = 0;
      try {
        final stats = await LanceDbService.getStats();
        finalCount = stats.totalEmbeddings.toInt();
      } catch (_) {}
      state = EmbeddingIndexState(
        isIndexing: false,
        totalItems: total,
        processedItems: total,
        indexedCount: finalCount,
      );
    }
  }
}
