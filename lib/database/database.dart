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

@DriftDatabase(tables: [VaultEntries, Notes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.addColumn(vaultEntries, vaultEntries.expiresAt);
          }
          if (from < 3) {
            await migrator.createTable(notes);
            // Migrate existing Note entries from vault_entries to notes
            await _migrateNotesToNewTable();
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
}
