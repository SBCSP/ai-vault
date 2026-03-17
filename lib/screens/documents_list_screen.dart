import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/document.dart';
import '../providers/auth_provider.dart';
import '../providers/documents_provider.dart';
import '../providers/embedding_provider.dart';
import '../services/document_service.dart';
import 'document_form_screen.dart';

class DocumentsListScreen extends ConsumerStatefulWidget {
  const DocumentsListScreen({super.key});

  @override
  ConsumerState<DocumentsListScreen> createState() =>
      _DocumentsListScreenState();
}

class _DocumentsListScreenState extends ConsumerState<DocumentsListScreen> {
  String _textFilter = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _textFilter = value),
              decoration: InputDecoration(
                hintText: 'Filter documents...',
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
            child: docsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (docs) {
                var filtered = docs;

                if (_textFilter.isNotEmpty) {
                  final q = _textFilter.toLowerCase();
                  filtered = filtered.where((d) {
                    return d.title.toLowerCase().contains(q) ||
                        d.filePath.toLowerCase().contains(q) ||
                        d.tags.toLowerCase().contains(q);
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
                          docs.isEmpty
                              ? Icons.description
                              : Icons.search_off,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          docs.isEmpty
                              ? 'No documents yet\nTap + to add your first document'
                              : 'No matching documents',
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
                    final doc = filtered[index];
                    return _DocumentTile(
                      document: doc,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DocumentFormScreen(document: doc),
                        ),
                      ),
                      onDelete: () => _confirmDelete(context, doc),
                      onReindex: () => _reindexDocument(doc),
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
          MaterialPageRoute(builder: (_) => const DocumentFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Document doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text(
          'Are you sure you want to delete "${doc.title}"?\n\n'
          'This will remove the document and all its indexed chunks. '
          'The original file on disk will not be affected.',
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
              ref.read(documentActionsProvider).deleteDocument(doc.id);
              ref
                  .read(embeddingIndexProvider.notifier)
                  .refreshStats();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _reindexDocument(Document doc) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Re-indexing "${doc.title}"...')),
    );
    await ref.read(embeddingIndexProvider.notifier).indexDocument(doc);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${doc.title}" re-indexed')),
      );
    }
  }
}

class _DocumentTile extends StatelessWidget {
  final Document document;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onReindex;

  const _DocumentTile({
    required this.document,
    required this.onTap,
    required this.onDelete,
    required this.onReindex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = document.updatedAt;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    // Truncate file path for display
    final pathDisplay = document.filePath.length > 50
        ? '...${document.filePath.substring(document.filePath.length - 47)}'
        : document.filePath;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            _iconForFileType(document.fileType),
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          document.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pathDisplay,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            Row(
              children: [
                Text(
                  '${document.chunkCount} chunks',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  document.fileType.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'reindex':
                onReindex();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'reindex',
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 18),
                  SizedBox(width: 8),
                  Text('Re-index'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Text('Delete',
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  IconData _iconForFileType(String fileType) {
    switch (fileType) {
      case 'md':
        return Icons.article;
      case 'json':
        return Icons.data_object;
      case 'yaml':
        return Icons.settings;
      case 'csv':
        return Icons.table_chart;
      default:
        return Icons.description;
    }
  }
}
