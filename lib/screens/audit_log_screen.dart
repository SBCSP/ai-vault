import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../providers/audit_provider.dart';
import '../providers/auth_provider.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(auditLogsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear all logs',
            onPressed: () => _confirmClear(context),
          ),
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _filter = v),
              decoration: InputDecoration(
                hintText: 'Filter logs...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          Expanded(
            child: logsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (logs) {
                var filtered = logs;
                if (_filter.isNotEmpty) {
                  final q = _filter.toLowerCase();
                  filtered = filtered.where((l) {
                    return l.action.toLowerCase().contains(q) ||
                        l.targetName.toLowerCase().contains(q) ||
                        l.targetType.toLowerCase().contains(q) ||
                        l.details.toLowerCase().contains(q);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          logs.isEmpty
                              ? 'No activity recorded yet'
                              : 'No matching logs',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final log = filtered[index];
                    return _AuditLogTile(log: log);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Audit Log'),
        content: const Text(
          'This will permanently delete all audit log entries. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(auditLoggerProvider).clearAll();
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

class _AuditLogTile extends StatelessWidget {
  final AuditLog log;

  const _AuditLogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = log.createdAt;
    final timeStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';

    final actionInfo = _actionDisplay(log.action);

    final detail = log.targetName.isNotEmpty
        ? log.targetName
        : log.details.isNotEmpty
            ? log.details
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Row(
        children: [
          Text(
            timeStr,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          Icon(actionInfo.icon, size: 14, color: actionInfo.color),
          const SizedBox(width: 8),
          Container(
            width: 110,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: actionInfo.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              actionInfo.label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: actionInfo.color,
                fontSize: 10,
              ),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detail,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static ({IconData icon, Color color, String label}) _actionDisplay(
      String action) {
    switch (action) {
      // Auth
      case AuditAction.vaultCreated:
        return (icon: Icons.add_circle, color: Colors.green, label: 'VAULT CREATED');
      case AuditAction.vaultUnlocked:
        return (icon: Icons.lock_open, color: Colors.green, label: 'UNLOCKED');
      case AuditAction.vaultLocked:
        return (icon: Icons.lock, color: Colors.blueGrey, label: 'LOCKED');
      case AuditAction.vaultUnlockFailed:
        return (icon: Icons.error, color: Colors.red, label: 'UNLOCK FAILED');

      // Secrets
      case AuditAction.secretCreated:
        return (icon: Icons.add, color: Colors.blue, label: 'SECRET CREATED');
      case AuditAction.secretUpdated:
        return (icon: Icons.edit, color: Colors.orange, label: 'SECRET UPDATED');
      case AuditAction.secretDeleted:
        return (icon: Icons.delete, color: Colors.red, label: 'SECRET DELETED');

      // Notes
      case AuditAction.noteCreated:
        return (icon: Icons.add, color: Colors.blue, label: 'NOTE CREATED');
      case AuditAction.noteUpdated:
        return (icon: Icons.edit, color: Colors.orange, label: 'NOTE UPDATED');
      case AuditAction.noteDeleted:
        return (icon: Icons.delete, color: Colors.red, label: 'NOTE DELETED');

      // Ideas
      case AuditAction.ideaCreated:
        return (icon: Icons.lightbulb, color: Colors.amber, label: 'IDEA CREATED');
      case AuditAction.ideaUpdated:
        return (icon: Icons.edit, color: Colors.orange, label: 'IDEA UPDATED');
      case AuditAction.ideaDeleted:
        return (icon: Icons.delete, color: Colors.red, label: 'IDEA DELETED');

      // Documents
      case AuditAction.documentAdded:
        return (icon: Icons.upload_file, color: Colors.blue, label: 'DOC ADDED');
      case AuditAction.documentUpdated:
        return (icon: Icons.edit, color: Colors.orange, label: 'DOC UPDATED');
      case AuditAction.documentDeleted:
        return (icon: Icons.delete, color: Colors.red, label: 'DOC DELETED');
      case AuditAction.documentIndexed:
        return (icon: Icons.search, color: Colors.deepPurple, label: 'DOC INDEXED');
      case AuditAction.directoryMapped:
        return (icon: Icons.folder, color: Colors.teal, label: 'DIR MAPPED');
      case AuditAction.indexAllStarted:
        return (icon: Icons.sync, color: Colors.deepPurple, label: 'INDEX ALL');
      case AuditAction.indexAllCompleted:
        return (icon: Icons.check_circle, color: Colors.green, label: 'INDEX DONE');

      // AWS
      case AuditAction.awsConnected:
        return (icon: Icons.cloud_done, color: Colors.green, label: 'AWS CONNECTED');
      case AuditAction.awsDisconnected:
        return (icon: Icons.cloud_off, color: Colors.grey, label: 'AWS DISCONNECTED');
      case AuditAction.awsSyncStarted:
        return (icon: Icons.sync, color: Colors.orange, label: 'AWS SYNC');
      case AuditAction.awsSyncCompleted:
        return (icon: Icons.cloud_download, color: Colors.green, label: 'AWS SYNCED');
      case AuditAction.awsConfigChanged:
        return (icon: Icons.settings, color: Colors.teal, label: 'AWS CONFIG');

      // Chat
      case AuditAction.chatSaved:
        return (icon: Icons.save, color: Colors.cyan, label: 'CHAT SAVED');
      case AuditAction.chatDeleted:
        return (icon: Icons.delete, color: Colors.red, label: 'CHAT DELETED');

      // Settings
      case AuditAction.settingsModelChanged:
      case AuditAction.settingsServerUrlChanged:
      case AuditAction.settingsEmbeddingModelChanged:
      case AuditAction.settingsTimeoutChanged:
      case AuditAction.settingsApiToggled:
      case AuditAction.settingsCategoryAdded:
      case AuditAction.settingsCategoryRemoved:
        return (icon: Icons.settings, color: Colors.teal, label: 'SETTINGS');

      // Embedding
      case AuditAction.reindexAllStarted:
        return (icon: Icons.sync, color: Colors.deepPurple, label: 'REINDEX');
      case AuditAction.reindexAllCompleted:
        return (icon: Icons.check_circle, color: Colors.green, label: 'REINDEX DONE');

      // Secrets Lock
      case AuditAction.secretsLocked:
        return (icon: Icons.lock, color: Colors.red, label: 'SECRETS LOCKED');
      case AuditAction.secretsUnlocked:
        return (icon: Icons.lock_open, color: Colors.green, label: 'SECRETS UNLOCKED');

      // MCP
      case AuditAction.mcpServerAdded:
        return (icon: Icons.extension, color: Colors.blue, label: 'MCP ADDED');
      case AuditAction.mcpServerRemoved:
        return (icon: Icons.extension_off, color: Colors.red, label: 'MCP REMOVED');
      case AuditAction.mcpConnected:
        return (icon: Icons.power, color: Colors.green, label: 'MCP CONNECTED');
      case AuditAction.mcpDisconnected:
        return (icon: Icons.power_off, color: Colors.grey, label: 'MCP DISCONNECTED');
      case AuditAction.mcpConnectionFailed:
        return (icon: Icons.error, color: Colors.red, label: 'MCP FAILED');
      case AuditAction.mcpToolCalled:
        return (icon: Icons.build, color: Colors.deepPurple, label: 'MCP TOOL CALL');
      case AuditAction.mcpToolFailed:
        return (icon: Icons.build_circle, color: Colors.red, label: 'MCP TOOL FAIL');

      default:
        return (icon: Icons.info, color: Colors.grey, label: action.toUpperCase());
    }
  }
}
