import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vault_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import 'entry_form_screen.dart';
import 'note_form_screen.dart';

class ExpiredSecretsScreen extends ConsumerWidget {
  const ExpiredSecretsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(vaultEntriesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expired Secrets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          final expired = entries
              .where((e) => e.isExpired)
              .toList()
            ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));

          if (expired.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.green.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No expired secrets!',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All your secrets are up to date.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: expired.length,
            itemBuilder: (context, index) {
              final entry = expired[index];
              return _ExpiredEntryTile(entry: entry);
            },
          );
        },
      ),
    );
  }
}

class _ExpiredEntryTile extends ConsumerWidget {
  final VaultEntry entry;

  const _ExpiredEntryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expiresAt = entry.expiresAt!;
    final daysAgo = DateTime.now().difference(expiresAt).inDays;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.error.withValues(alpha: 0.15),
          child: Icon(
            _categoryIcon(entry.category),
            color: theme.colorScheme.error,
            size: 20,
          ),
        ),
        title: Text(
          entry.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${entry.category} \u2022 Expired ${daysAgo}d ago\n'
          '${expiresAt.year}-${expiresAt.month.toString().padLeft(2, '0')}-${expiresAt.day.toString().padLeft(2, '0')}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
          tooltip: 'Delete',
          onPressed: () => _confirmDelete(context, ref),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => entry.category.toLowerCase() == 'note'
                ? NoteFormScreen(entry: entry)
                : EntryFormScreen(entry: entry),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Secret'),
        content: Text(
          'Are you sure you want to delete "${entry.title}"? '
          'This cannot be undone.',
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
              ref.read(vaultActionsProvider).deleteEntry(entry.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'login':
        return Icons.login;
      case 'api key':
        return Icons.key;
      case 'credit card':
        return Icons.credit_card;
      case 'note':
        return Icons.note;
      case 'ssh key':
        return Icons.terminal;
      case 'wifi':
        return Icons.wifi;
      default:
        return Icons.lock;
    }
  }
}
