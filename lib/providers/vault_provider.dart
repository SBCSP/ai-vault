import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/vault_entry.dart' as model;
import '../services/encryption_service.dart';
import 'auth_provider.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final vaultEntriesProvider =
    StreamProvider<List<model.VaultEntry>>((ref) {
  final db = ref.read(databaseProvider);
  final encryption = ref.read(encryptionServiceProvider);

  return db.watchAllEntries().map((entries) {
    return entries.map((e) => _decryptEntry(e, encryption)).toList();
  });
});

final vaultActionsProvider = Provider<VaultActions>((ref) {
  return VaultActions(
    db: ref.read(databaseProvider),
    encryption: ref.read(encryptionServiceProvider),
  );
});

model.VaultEntry _decryptEntry(VaultEntry e, EncryptionService encryption) {
  return model.VaultEntry(
    id: e.id,
    title: e.title,
    username: e.username,
    password:
        e.password.isNotEmpty ? encryption.decrypt(e.password) : '',
    url: e.url,
    notes: e.notes.isNotEmpty ? encryption.decrypt(e.notes) : '',
    category: e.category,
    tags: e.tags,
    createdAt: e.createdAt,
    updatedAt: e.updatedAt,
    expiresAt: e.expiresAt,
  );
}

class VaultActions {
  final AppDatabase _db;
  final EncryptionService _encryption;
  static const _uuid = Uuid();

  VaultActions({required AppDatabase db, required EncryptionService encryption})
      : _db = db,
        _encryption = encryption;

  Future<String> addEntry(model.VaultEntry entry) async {
    final now = DateTime.now();
    final id = entry.id.isEmpty ? _uuid.v4() : entry.id;

    await _db.insertEntry(VaultEntriesCompanion.insert(
      id: id,
      title: entry.title,
      username: Value(entry.username),
      password: Value(
        entry.password.isNotEmpty
            ? _encryption.encrypt(entry.password)
            : '',
      ),
      url: Value(entry.url),
      notes: Value(
        entry.notes.isNotEmpty ? _encryption.encrypt(entry.notes) : '',
      ),
      category: Value(entry.category),
      tags: Value(entry.tags),
      createdAt: now,
      updatedAt: now,
      expiresAt: Value(entry.expiresAt),
    ));

    return id;
  }

  Future<void> updateEntry(model.VaultEntry entry) async {
    await _db.updateEntry(VaultEntriesCompanion(
      id: Value(entry.id),
      title: Value(entry.title),
      username: Value(entry.username),
      password: Value(
        entry.password.isNotEmpty
            ? _encryption.encrypt(entry.password)
            : '',
      ),
      url: Value(entry.url),
      notes: Value(
        entry.notes.isNotEmpty ? _encryption.encrypt(entry.notes) : '',
      ),
      category: Value(entry.category),
      tags: Value(entry.tags),
      updatedAt: Value(DateTime.now()),
      expiresAt: Value(entry.expiresAt),
    ));
  }

  Future<void> deleteEntry(String id) async {
    await _db.deleteEntry(id);
  }
}
