import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart' as db;
import '../models/document.dart' as model;
import 'vault_provider.dart';

final documentsProvider = StreamProvider<List<model.Document>>((ref) {
  final database = ref.read(databaseProvider);

  return database.watchAllDocuments().map((docs) {
    return docs
        .map((d) => model.Document(
              id: d.id,
              title: d.title,
              filePath: d.filePath,
              fileType: d.fileType,
              chunkCount: d.chunkCount,
              contentHash: d.contentHash,
              tags: d.tags,
              createdAt: d.createdAt,
              updatedAt: d.updatedAt,
              lastIndexedAt: d.lastIndexedAt,
            ))
        .toList();
  });
});

final documentActionsProvider = Provider<DocumentActions>((ref) {
  return DocumentActions(db: ref.read(databaseProvider));
});

class DocumentActions {
  final db.AppDatabase _db;
  static const _uuid = Uuid();

  DocumentActions({required db.AppDatabase db}) : _db = db;

  Future<String> addDocument(model.Document doc) async {
    final now = DateTime.now();
    final id = doc.id.isEmpty ? _uuid.v4() : doc.id;

    await _db.insertDocument(db.DocumentsCompanion.insert(
      id: id,
      title: doc.title,
      filePath: doc.filePath,
      fileType: Value(doc.fileType),
      chunkCount: Value(doc.chunkCount),
      contentHash: Value(doc.contentHash),
      tags: Value(doc.tags),
      createdAt: now,
      updatedAt: now,
      lastIndexedAt: Value(doc.lastIndexedAt),
    ));

    return id;
  }

  Future<void> updateDocument(model.Document doc) async {
    await _db.updateDocument(db.DocumentsCompanion(
      id: Value(doc.id),
      title: Value(doc.title),
      filePath: Value(doc.filePath),
      fileType: Value(doc.fileType),
      chunkCount: Value(doc.chunkCount),
      contentHash: Value(doc.contentHash),
      tags: Value(doc.tags),
      updatedAt: Value(DateTime.now()),
      lastIndexedAt: Value(doc.lastIndexedAt),
    ));
  }

  Future<void> deleteDocument(String id) async {
    // Delete chunks and their embeddings first
    final chunks = await _db.getChunksByDocumentId(id);
    for (final chunk in chunks) {
      await _db.deleteEmbeddingBySourceId(chunk.id);
    }
    await _db.deleteChunksByDocumentId(id);
    await _db.deleteDocument(id);
  }
}
