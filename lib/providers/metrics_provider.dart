import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import 'audit_provider.dart';
import 'chat_history_provider.dart';
import 'documents_provider.dart';
import 'ideas_provider.dart';
import 'notes_provider.dart';
import 'server_provider.dart';
import 'vault_provider.dart';

/// Format a DateTime as yyyy-MM-dd string.
String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Snapshot today's counts into the daily_metrics table.
Future<void> recordDailySnapshot(AppDatabase db) async {
  final today = _dateKey(DateTime.now());

  final secrets = await db.getAllEntries();
  final notes = await db.getAllNotes();
  final ideas = await db.getAllIdeas();
  final docs = await db.getAllDocuments();
  final chats = (await db.select(db.chatSessions).get()).length;
  final servers = (await db.select(db.servers).get()).length;

  final now = DateTime.now();
  final expired = secrets
      .where((e) => e.expiresAt != null && e.expiresAt!.isBefore(now))
      .length;
  final expiringSoon = secrets
      .where((e) =>
          e.expiresAt != null &&
          !e.expiresAt!.isBefore(now) &&
          e.expiresAt!.isBefore(now.add(const Duration(days: 30))))
      .length;

  await db.upsertDailyMetric(DailyMetricsCompanion(
    date: Value(today),
    secretsCount: Value(secrets.length),
    notesCount: Value(notes.length),
    ideasCount: Value(ideas.length),
    documentsCount: Value(docs.length),
    chatsCount: Value(chats),
    serversCount: Value(servers),
    expiredCount: Value(expired),
    expiringSoonCount: Value(expiringSoon),
    createdAt: Value(DateTime.now()),
  ));
}

/// Provides the last N days of metrics for charts.
/// Watches all data streams so it auto-updates when items are added/removed.
final metricsTimeseriesProvider =
    FutureProvider.family<List<DailyMetric>, int>((ref, days) async {
  final db = ref.read(databaseProvider);

  // Watch all data sources so this provider refreshes on any mutation.
  ref.watch(vaultEntriesProvider);
  ref.watch(notesProvider);
  ref.watch(ideasProvider);
  ref.watch(documentsProvider);
  ref.watch(chatSessionsProvider);
  ref.watch(serversProvider);

  // Re-snapshot today's row with current counts
  await recordDailySnapshot(db);

  final since = DateTime.now().subtract(Duration(days: days));
  return db.getMetricsSince(since);
});

/// Provides all-time metrics.
final allMetricsProvider = FutureProvider<List<DailyMetric>>((ref) async {
  final db = ref.read(databaseProvider);

  ref.watch(vaultEntriesProvider);
  ref.watch(notesProvider);
  ref.watch(ideasProvider);
  ref.watch(documentsProvider);
  ref.watch(chatSessionsProvider);
  ref.watch(serversProvider);

  await recordDailySnapshot(db);
  return db.getAllMetrics();
});

// ──────────────────────────────────────────────
// Audit-derived activity timeseries
// ──────────────────────────────────────────────

/// Daily counts for each audit category, keyed by date string.
class DailyActivity {
  final String date;
  final int totalEvents;
  final int creates;
  final int updates;
  final int deletes;
  final int unlocks;
  final int unlockFailures;
  final int locks;
  final int chatSaves;
  final int mcpToolCalls;
  final int mcpToolFailures;
  final int settingsChanges;
  final int indexingOps;
  final int awsOps;
  final int secretsLockEvents;

  const DailyActivity({
    required this.date,
    this.totalEvents = 0,
    this.creates = 0,
    this.updates = 0,
    this.deletes = 0,
    this.unlocks = 0,
    this.unlockFailures = 0,
    this.locks = 0,
    this.chatSaves = 0,
    this.mcpToolCalls = 0,
    this.mcpToolFailures = 0,
    this.settingsChanges = 0,
    this.indexingOps = 0,
    this.awsOps = 0,
    this.secretsLockEvents = 0,
  });
}

/// Categorize an audit action string into counters.
void _categorize(String action, _ActivityAccumulator acc) {
  acc.totalEvents++;

  // CRUD
  if (action.endsWith('.created') || action == AuditAction.documentAdded) {
    acc.creates++;
  } else if (action.endsWith('.updated')) {
    acc.updates++;
  } else if (action.endsWith('.deleted')) {
    acc.deletes++;
  }

  // Security
  if (action == AuditAction.vaultUnlocked) acc.unlocks++;
  if (action == AuditAction.vaultUnlockFailed) acc.unlockFailures++;
  if (action == AuditAction.vaultLocked) acc.locks++;

  // Secrets lock
  if (action == AuditAction.secretsLocked ||
      action == AuditAction.secretsUnlocked) {
    acc.secretsLockEvents++;
  }

  // Chat
  if (action == AuditAction.chatSaved) acc.chatSaves++;

  // MCP
  if (action == AuditAction.mcpToolCalled) acc.mcpToolCalls++;
  if (action == AuditAction.mcpToolFailed) acc.mcpToolFailures++;

  // Settings
  if (action.startsWith('settings.')) acc.settingsChanges++;

  // Indexing / embedding
  if (action == AuditAction.documentIndexed ||
      action == AuditAction.indexAllStarted ||
      action == AuditAction.indexAllCompleted ||
      action == AuditAction.reindexAllStarted ||
      action == AuditAction.reindexAllCompleted ||
      action == AuditAction.directoryMapped) {
    acc.indexingOps++;
  }

  // AWS
  if (action.startsWith('aws.')) acc.awsOps++;
}

class _ActivityAccumulator {
  int totalEvents = 0;
  int creates = 0;
  int updates = 0;
  int deletes = 0;
  int unlocks = 0;
  int unlockFailures = 0;
  int locks = 0;
  int chatSaves = 0;
  int mcpToolCalls = 0;
  int mcpToolFailures = 0;
  int settingsChanges = 0;
  int indexingOps = 0;
  int awsOps = 0;
  int secretsLockEvents = 0;

  DailyActivity toActivity(String date) => DailyActivity(
        date: date,
        totalEvents: totalEvents,
        creates: creates,
        updates: updates,
        deletes: deletes,
        unlocks: unlocks,
        unlockFailures: unlockFailures,
        locks: locks,
        chatSaves: chatSaves,
        mcpToolCalls: mcpToolCalls,
        mcpToolFailures: mcpToolFailures,
        settingsChanges: settingsChanges,
        indexingOps: indexingOps,
        awsOps: awsOps,
        secretsLockEvents: secretsLockEvents,
      );
}

/// Provides audit-derived daily activity timeseries for the last N days.
/// Watches the audit log stream so it auto-updates.
final activityTimeseriesProvider =
    FutureProvider.family<List<DailyActivity>, int>((ref, days) async {
  final db = ref.read(databaseProvider);

  // Watch audit logs so this refreshes when new events are logged
  ref.watch(auditLogsProvider);

  final since = DateTime.now().subtract(Duration(days: days));
  final logs = await db.getAuditLogsSince(since);

  // Group by date
  final buckets = <String, _ActivityAccumulator>{};
  for (final log in logs) {
    final key = _dateKey(log.createdAt);
    final acc = buckets.putIfAbsent(key, () => _ActivityAccumulator());
    _categorize(log.action, acc);
  }

  // Convert to sorted list, filling in empty days
  final result = <DailyActivity>[];
  var cursor = DateTime(since.year, since.month, since.day);
  final today = DateTime.now();
  while (!cursor.isAfter(today)) {
    final key = _dateKey(cursor);
    result.add(buckets.containsKey(key)
        ? buckets[key]!.toActivity(key)
        : DailyActivity(date: key));
    cursor = cursor.add(const Duration(days: 1));
  }

  return result;
});
