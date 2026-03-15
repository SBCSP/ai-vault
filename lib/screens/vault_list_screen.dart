import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../widgets/vault_entry_tile.dart';
import 'entry_form_screen.dart';
import 'note_form_screen.dart';

class VaultListScreen extends ConsumerStatefulWidget {
  const VaultListScreen({super.key});

  @override
  ConsumerState<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends ConsumerState<VaultListScreen> {
  String _textFilter = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(vaultEntriesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Secrets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Simple local search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _textFilter = value),
              decoration: InputDecoration(
                hintText: 'Filter secrets...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _textFilter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _textFilter = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          Expanded(
            child: entriesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (entries) {
                var filtered = entries;

                if (_textFilter.isNotEmpty) {
                  final q = _textFilter.toLowerCase();
                  filtered = filtered.where((e) {
                    return e.title.toLowerCase().contains(q) ||
                        e.username.toLowerCase().contains(q) ||
                        e.url.toLowerCase().contains(q) ||
                        e.category.toLowerCase().contains(q) ||
                        e.tags.toLowerCase().contains(q);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          entries.isEmpty
                              ? Icons.lock_open
                              : Icons.search_off,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          entries.isEmpty
                              ? 'Your vault is empty\nTap + to add your first entry'
                              : 'No matching entries',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return VaultEntryTile(
                      entry: entry,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => entry.category.toLowerCase() == 'note'
                              ? NoteFormScreen(entry: entry)
                              : EntryFormScreen(entry: entry),
                        ),
                      ),
                      onDelete: () => ref
                          .read(vaultActionsProvider)
                          .deleteEntry(entry.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EntryFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}
