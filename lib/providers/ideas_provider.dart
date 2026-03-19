import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart' as db;
import '../models/idea.dart' as model;
import '../services/encryption_service.dart';
import 'audit_provider.dart';
import 'auth_provider.dart';
import 'vault_provider.dart';

final ideasProvider = StreamProvider<List<model.Idea>>((ref) {
  final database = ref.read(databaseProvider);
  final encryption = ref.read(encryptionServiceProvider);

  return database.watchAllIdeas().map((ideas) {
    return ideas.map((i) => _decryptIdea(i, encryption)).toList();
  });
});

final ideaActionsProvider = Provider<IdeaActions>((ref) {
  return IdeaActions(
    db: ref.read(databaseProvider),
    encryption: ref.read(encryptionServiceProvider),
    audit: ref.read(auditLoggerProvider),
  );
});

model.Idea _decryptIdea(db.Idea i, EncryptionService encryption) {
  return model.Idea(
    id: i.id,
    title: i.title,
    body: i.body.isNotEmpty ? encryption.decrypt(i.body) : '',
    tags: i.tags,
    createdAt: i.createdAt,
    updatedAt: i.updatedAt,
  );
}

class IdeaActions {
  final db.AppDatabase _db;
  final EncryptionService _encryption;
  final AuditLogger _audit;
  static const _uuid = Uuid();

  IdeaActions({
    required db.AppDatabase db,
    required EncryptionService encryption,
    required AuditLogger audit,
  })  : _db = db,
        _encryption = encryption,
        _audit = audit;

  Future<String> addIdea(model.Idea idea) async {
    final now = DateTime.now();
    final id = idea.id.isEmpty ? _uuid.v4() : idea.id;

    await _db.insertIdea(db.IdeasCompanion.insert(
      id: id,
      title: idea.title,
      body: Value(
        idea.body.isNotEmpty ? _encryption.encrypt(idea.body) : '',
      ),
      tags: Value(idea.tags),
      createdAt: now,
      updatedAt: now,
    ));

    await _audit.log(
      action: AuditAction.ideaCreated,
      targetType: 'idea',
      targetId: id,
      targetName: idea.title,
    );

    return id;
  }

  Future<void> updateIdea(model.Idea idea) async {
    await _db.updateIdea(db.IdeasCompanion(
      id: Value(idea.id),
      title: Value(idea.title),
      body: Value(
        idea.body.isNotEmpty ? _encryption.encrypt(idea.body) : '',
      ),
      tags: Value(idea.tags),
      updatedAt: Value(DateTime.now()),
    ));

    await _audit.log(
      action: AuditAction.ideaUpdated,
      targetType: 'idea',
      targetId: idea.id,
      targetName: idea.title,
    );
  }

  Future<void> deleteIdea(String id) async {
    await _audit.log(
      action: AuditAction.ideaDeleted,
      targetType: 'idea',
      targetId: id,
    );
    await _db.deleteIdea(id);
  }
}
