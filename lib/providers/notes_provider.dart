import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart' as db;
import '../models/note.dart' as model;
import '../services/encryption_service.dart';
import 'audit_provider.dart';
import 'auth_provider.dart';
import 'vault_provider.dart';

final notesProvider = StreamProvider<List<model.Note>>((ref) {
  final database = ref.read(databaseProvider);
  final encryption = ref.read(encryptionServiceProvider);

  return database.watchAllNotes().map((notes) {
    return notes.map((n) => _decryptNote(n, encryption)).toList();
  });
});

final noteActionsProvider = Provider<NoteActions>((ref) {
  return NoteActions(
    db: ref.read(databaseProvider),
    encryption: ref.read(encryptionServiceProvider),
    audit: ref.read(auditLoggerProvider),
  );
});

model.Note _decryptNote(db.Note n, EncryptionService encryption) {
  return model.Note(
    id: n.id,
    title: n.title,
    body: n.body.isNotEmpty ? encryption.decrypt(n.body) : '',
    tags: n.tags,
    createdAt: n.createdAt,
    updatedAt: n.updatedAt,
  );
}

class NoteActions {
  final db.AppDatabase _db;
  final EncryptionService _encryption;
  final AuditLogger _audit;
  static const _uuid = Uuid();

  NoteActions({
    required db.AppDatabase db,
    required EncryptionService encryption,
    required AuditLogger audit,
  })  : _db = db,
        _encryption = encryption,
        _audit = audit;

  Future<String> addNote(model.Note note) async {
    final now = DateTime.now();
    final id = note.id.isEmpty ? _uuid.v4() : note.id;

    await _db.insertNote(db.NotesCompanion.insert(
      id: id,
      title: note.title,
      body: Value(
        note.body.isNotEmpty ? _encryption.encrypt(note.body) : '',
      ),
      tags: Value(note.tags),
      createdAt: now,
      updatedAt: now,
    ));

    await _audit.log(
      action: AuditAction.noteCreated,
      targetType: 'note',
      targetId: id,
      targetName: note.title,
    );

    return id;
  }

  Future<void> updateNote(model.Note note) async {
    await _db.updateNote(db.NotesCompanion(
      id: Value(note.id),
      title: Value(note.title),
      body: Value(
        note.body.isNotEmpty ? _encryption.encrypt(note.body) : '',
      ),
      tags: Value(note.tags),
      updatedAt: Value(DateTime.now()),
    ));

    await _audit.log(
      action: AuditAction.noteUpdated,
      targetType: 'note',
      targetId: note.id,
      targetName: note.title,
    );
  }

  Future<void> deleteNote(String id) async {
    await _audit.log(
      action: AuditAction.noteDeleted,
      targetType: 'note',
      targetId: id,
    );
    await _db.deleteNote(id);
  }
}
