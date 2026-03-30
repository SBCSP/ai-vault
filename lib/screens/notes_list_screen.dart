import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/auth_provider.dart';
import '../providers/embedding_provider.dart';
import '../providers/notes_provider.dart';
import 'note_form_screen.dart';

class NotesListScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const NotesListScreen({super.key, this.embedded = false});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  String _textFilter = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider);
    final theme = Theme.of(context);

    final body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _textFilter = value),
              decoration: InputDecoration(
                hintText: 'Filter notes...',
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
            child: notesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (notes) {
                var filtered = notes;

                if (_textFilter.isNotEmpty) {
                  final q = _textFilter.toLowerCase();
                  filtered = filtered.where((n) {
                    return n.title.toLowerCase().contains(q) ||
                        n.body.toLowerCase().contains(q) ||
                        n.tags.toLowerCase().contains(q);
                  }).toList();
                }

                // Sort by most recently updated
                filtered = [...filtered]
                  ..sort(
                      (a, b) => b.updatedAt.compareTo(a.updatedAt));

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          notes.isEmpty
                              ? Icons.note_add
                              : Icons.search_off,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          notes.isEmpty
                              ? 'No notes yet\nTap + to create your first note'
                              : 'No matching notes',
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
                    final note = filtered[index];
                    return _NoteTile(
                      note: note,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NoteFormScreen(note: note),
                        ),
                      ),
                      onDelete: () => _confirmDelete(context, note),
                    );
                  },
                );
              },
            ),
          ),
        ],
      );

    final fab = FloatingActionButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NoteFormScreen()),
      ),
      child: const Icon(Icons.note_add),
    );

    if (widget.embedded) {
      return Scaffold(body: body, floatingActionButton: fab);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      body: body,
      floatingActionButton: fab,
    );
  }

  void _confirmDelete(BuildContext context, Note note) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text(
          'Are you sure you want to delete "${note.title}"? '
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
              ref.read(noteActionsProvider).deleteNote(note.id);
              ref.read(embeddingIndexProvider.notifier).removeNote(note.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NoteTile({
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = note.updatedAt;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    // Preview: first line of body, truncated
    final preview = note.body.isNotEmpty
        ? note.body.split('\n').first.trim()
        : 'Empty note';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.tertiaryContainer,
          child: Icon(
            Icons.note,
            color: theme.colorScheme.onTertiaryContainer,
          ),
        ),
        title: Text(
          note.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            Text(
              dateStr,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline,
            color: theme.colorScheme.error,
          ),
          tooltip: 'Delete',
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }
}
