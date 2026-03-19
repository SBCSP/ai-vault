import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import 'vault_provider.dart';

/// Watches the most recent audit logs (reactive stream).
final auditLogsProvider = StreamProvider<List<AuditLog>>((ref) {
  final database = ref.read(databaseProvider);
  return database.watchAuditLogs(limit: 200);
});

/// Provides the AuditLogger for writing log entries.
final auditLoggerProvider = Provider<AuditLogger>((ref) {
  return AuditLogger(ref.read(databaseProvider));
});

class AuditLogger {
  final AppDatabase _db;

  AuditLogger(this._db);

  Future<void> log({
    required String action,
    String targetType = '',
    String targetId = '',
    String targetName = '',
    String details = '',
  }) async {
    await _db.insertAuditLog(AuditLogsCompanion.insert(
      action: action,
      targetType: Value(targetType),
      targetId: Value(targetId),
      targetName: Value(targetName),
      details: Value(details),
      createdAt: DateTime.now(),
    ));
  }

  Future<void> clearAll() => _db.clearAuditLogs();
}

/// Standard action names used throughout the app.
abstract class AuditAction {
  // Auth
  static const String vaultCreated = 'vault.created';
  static const String vaultUnlocked = 'vault.unlocked';
  static const String vaultLocked = 'vault.locked';
  static const String vaultUnlockFailed = 'vault.unlock_failed';

  // Secrets
  static const String secretCreated = 'secret.created';
  static const String secretUpdated = 'secret.updated';
  static const String secretDeleted = 'secret.deleted';

  // Notes
  static const String noteCreated = 'note.created';
  static const String noteUpdated = 'note.updated';
  static const String noteDeleted = 'note.deleted';

  // Ideas
  static const String ideaCreated = 'idea.created';
  static const String ideaUpdated = 'idea.updated';
  static const String ideaDeleted = 'idea.deleted';

  // Documents
  static const String documentAdded = 'document.added';
  static const String documentUpdated = 'document.updated';
  static const String documentDeleted = 'document.deleted';
  static const String documentIndexed = 'document.indexed';
  static const String directoryMapped = 'directory.mapped';
  static const String indexAllStarted = 'index.all_started';
  static const String indexAllCompleted = 'index.all_completed';

  // AWS
  static const String awsConnected = 'aws.connected';
  static const String awsDisconnected = 'aws.disconnected';
  static const String awsSyncStarted = 'aws.sync_started';
  static const String awsSyncCompleted = 'aws.sync_completed';
  static const String awsConfigChanged = 'aws.config_changed';

  // Chat
  static const String chatSaved = 'chat.saved';
  static const String chatDeleted = 'chat.deleted';

  // Settings
  static const String settingsModelChanged = 'settings.model_changed';
  static const String settingsServerUrlChanged = 'settings.server_url_changed';
  static const String settingsEmbeddingModelChanged = 'settings.embedding_model_changed';
  static const String settingsTimeoutChanged = 'settings.timeout_changed';
  static const String settingsApiToggled = 'settings.api_toggled';
  static const String settingsCategoryAdded = 'settings.category_added';
  static const String settingsCategoryRemoved = 'settings.category_removed';

  // Embedding
  static const String reindexAllStarted = 'reindex.all_started';
  static const String reindexAllCompleted = 'reindex.all_completed';

  // Secrets Lock
  static const String secretsLocked = 'secrets.locked';
  static const String secretsUnlocked = 'secrets.unlocked';
}
