import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/idea.dart';
import '../providers/auth_provider.dart';
import '../providers/embedding_provider.dart';
import '../providers/ideas_provider.dart';
import 'idea_form_screen.dart';

class IdeasListScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const IdeasListScreen({super.key, this.embedded = false});

  @override
  ConsumerState<IdeasListScreen> createState() => _IdeasListScreenState();
}

class _IdeasListScreenState extends ConsumerState<IdeasListScreen> {
  String _textFilter = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ideasAsync = ref.watch(ideasProvider);
    final theme = Theme.of(context);

    final body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _textFilter = value),
              decoration: InputDecoration(
                hintText: 'Filter ideas...',
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
            child: ideasAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (ideas) {
                var filtered = ideas;

                if (_textFilter.isNotEmpty) {
                  final q = _textFilter.toLowerCase();
                  filtered = filtered.where((i) {
                    return i.title.toLowerCase().contains(q) ||
                        i.body.toLowerCase().contains(q) ||
                        i.tags.toLowerCase().contains(q);
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
                          ideas.isEmpty
                              ? Icons.lightbulb_outline
                              : Icons.search_off,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          ideas.isEmpty
                              ? 'No ideas yet\nTap + to capture your first idea'
                              : 'No matching ideas',
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
                    final idea = filtered[index];
                    return _IdeaTile(
                      idea: idea,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => IdeaFormScreen(idea: idea),
                        ),
                      ),
                      onDelete: () => _confirmDelete(context, idea),
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
        MaterialPageRoute(builder: (_) => const IdeaFormScreen()),
      ),
      child: const Icon(Icons.lightbulb),
    );

    if (widget.embedded) {
      return Scaffold(body: body, floatingActionButton: fab);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ideas'),
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

  void _confirmDelete(BuildContext context, Idea idea) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Idea'),
        content: Text(
          'Are you sure you want to delete "${idea.title}"? '
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
              ref.read(ideaActionsProvider).deleteIdea(idea.id);
              ref.read(embeddingIndexProvider.notifier).removeIdea(idea.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _IdeaTile extends StatelessWidget {
  final Idea idea;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _IdeaTile({
    required this.idea,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = idea.updatedAt;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    // Preview: first line of body, truncated
    final preview = idea.body.isNotEmpty
        ? idea.body.split('\n').first.trim()
        : 'Empty idea';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.amber.shade100,
          child: Icon(
            Icons.lightbulb,
            color: Colors.amber.shade700,
          ),
        ),
        title: Text(
          idea.title,
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
