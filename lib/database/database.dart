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

@DriftDatabase(tables: [VaultEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.addColumn(vaultEntries, vaultEntries.expiresAt);
          }
        },
      );

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
}
