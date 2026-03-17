import 'package:drift/drift.dart';

import 'connection/unsupported.dart'
    if (dart.library.ffi) 'connection/native.dart'
    if (dart.library.js_interop) 'connection/web.dart';

part 'database.g.dart';

class VaultEntries extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get username => text().withDefault(const Constant(''))();
  TextColumn get password => text().withDefault(const Constant(''))();
  TextColumn get url => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get category =>
      text().withDefault(const Constant('General'))();
  TextColumn get tags => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get tags => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Embeddings extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text()();
  TextColumn get sourceType =>
      text()(); // 'vault_entry', 'note', or 'document_chunk'
  TextColumn get embedding => text()(); // JSON-encoded List<double>
  TextColumn get modelName => text()();
  TextColumn get contentHash => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get filePath => text()();
  TextColumn get fileType => text().withDefault(const Constant('txt'))();
  IntColumn get chunkCount => integer().withDefault(const Constant(0))();
  TextColumn get contentHash => text().withDefault(const Constant(''))();
  TextColumn get tags => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastIndexedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class DocumentChunks extends Table {
  TextColumn get id => text()();
  TextColumn get documentId => text()();
  IntColumn get chunkIndex => integer()();
  TextColumn get content => text()();
  TextColumn get contentHash => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class ChatSessions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get messages => text()(); // JSON-encoded List<Map>
  BoolColumn get isIndexed =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  VaultEntries,
  Notes,
  Embeddings,
  Documents,
  DocumentChunks,
  ChatSessions,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.addColumn(vaultEntries, vaultEntries.expiresAt);
          }
          if (from < 3) {
            await migrator.createTable(notes);
            await _migrateNotesToNewTable();
          }
          if (from < 4) {
            await migrator.createTable(embeddings);
          }
          if (from < 5) {
            await migrator.createTable(documents);
            await migrator.createTable(documentChunks);
          }
          if (from < 6) {
            await migrator.createTable(chatSessions);
          }
        },
      );

  /// Migrate entries with category='Note' from vault_entries → notes table,
  /// then delete them from vault_entries.
  Future<void> _migrateNotesToNewTable() async {
    final noteEntries = await (select(vaultEntries)
          ..where((t) => t.category.equals('Note')))
        .get();

    for (final entry in noteEntries) {
      await into(notes).insert(NotesCompanion.insert(
        id: entry.id,
        title: entry.title,
        body: Value(entry.notes), // note body was stored in notes field
        tags: Value(entry.tags),
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt,
      ));
    }

    // Remove migrated notes from vault_entries
    await (delete(vaultEntries)..where((t) => t.category.equals('Note'))).go();
  }

  // --- Vault Entries ---
  Future<List<VaultEntry>> getAllEntries() => select(vaultEntries).get();

  Stream<List<VaultEntry>> watchAllEntries() => select(vaultEntries).watch();

  Future<void> insertEntry(VaultEntriesCompanion entry) =>
      into(vaultEntries).insert(entry);

  Future<void> updateEntry(VaultEntriesCompanion entry) =>
      (update(vaultEntries)..where((t) => t.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteEntry(String id) =>
      (delete(vaultEntries)..where((t) => t.id.equals(id))).go();

  Future<List<VaultEntry>> searchEntries(String query) {
    final lowerQuery = '%${query.toLowerCase()}%';
    return (select(vaultEntries)
          ..where((t) =>
              t.title.lower().like(lowerQuery) |
              t.username.lower().like(lowerQuery) |
              t.url.lower().like(lowerQuery) |
              t.category.lower().like(lowerQuery) |
              t.tags.lower().like(lowerQuery)))
        .get();
  }

  // --- Notes ---
  Future<List<Note>> getAllNotes() => select(notes).get();

  Stream<List<Note>> watchAllNotes() => select(notes).watch();

  Future<void> insertNote(NotesCompanion note) => into(notes).insert(note);

  Future<void> updateNote(NotesCompanion note) =>
      (update(notes)..where((t) => t.id.equals(note.id.value))).write(note);

  Future<void> deleteNote(String id) =>
      (delete(notes)..where((t) => t.id.equals(id))).go();

  // --- Embeddings ---
  Future<List<Embedding>> getAllEmbeddings() => select(embeddings).get();

  Future<Embedding?> getEmbeddingBySourceId(String sourceId) =>
      (select(embeddings)..where((t) => t.sourceId.equals(sourceId)))
          .getSingleOrNull();

  Future<void> upsertEmbedding(EmbeddingsCompanion entry) async {
    await into(embeddings).insertOnConflictUpdate(entry);
  }

  Future<void> deleteEmbeddingBySourceId(String sourceId) =>
      (delete(embeddings)..where((t) => t.sourceId.equals(sourceId))).go();

  Future<void> deleteAllEmbeddings() => delete(embeddings).go();

  Future<int> countEmbeddings() async {
    final count = countAll();
    final query = selectOnly(embeddings)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  // --- Documents ---
  Future<List<Document>> getAllDocuments() => select(documents).get();

  Stream<List<Document>> watchAllDocuments() => select(documents).watch();

  Future<Document?> getDocumentById(String id) =>
      (select(documents)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertDocument(DocumentsCompanion doc) =>
      into(documents).insert(doc);

  Future<void> updateDocument(DocumentsCompanion doc) =>
      (update(documents)..where((t) => t.id.equals(doc.id.value))).write(doc);

  Future<void> deleteDocument(String id) =>
      (delete(documents)..where((t) => t.id.equals(id))).go();

  // --- Document Chunks ---
  Future<List<DocumentChunk>> getChunksByDocumentId(String documentId) =>
      (select(documentChunks)
            ..where((t) => t.documentId.equals(documentId))
            ..orderBy([(t) => OrderingTerm.asc(t.chunkIndex)]))
          .get();

  Future<void> insertDocumentChunk(DocumentChunksCompanion chunk) =>
      into(documentChunks).insert(chunk);

  Future<void> deleteChunksByDocumentId(String documentId) =>
      (delete(documentChunks)..where((t) => t.documentId.equals(documentId)))
          .go();

  Future<List<DocumentChunk>> getChunksByIds(List<String> ids) =>
      (select(documentChunks)..where((t) => t.id.isIn(ids))).get();

  // --- Chat Sessions ---
  Stream<List<ChatSession>> watchAllChatSessions() =>
      (select(chatSessions)
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .watch();

  Future<ChatSession?> getChatSessionById(String id) =>
      (select(chatSessions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> insertChatSession(ChatSessionsCompanion session) =>
      into(chatSessions).insert(session);

  Future<void> updateChatSession(ChatSessionsCompanion session) =>
      (update(chatSessions)..where((t) => t.id.equals(session.id.value)))
          .write(session);

  Future<void> deleteChatSession(String id) =>
      (delete(chatSessions)..where((t) => t.id.equals(id))).go();

  Future<List<ChatSession>> getIndexedChatSessions() =>
      (select(chatSessions)..where((t) => t.isIndexed.equals(true))).get();
}
