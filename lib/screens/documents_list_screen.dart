import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/document.dart';
import '../providers/auth_provider.dart';
import '../providers/documents_provider.dart';
import '../providers/embedding_provider.dart';
import '../services/document_service.dart';
import 'document_form_screen.dart';

class DocumentsListScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const DocumentsListScreen({super.key, this.embedded = false});

  @override
  ConsumerState<DocumentsListScreen> createState() =>
      _DocumentsListScreenState();
}

class _DocumentsListScreenState extends ConsumerState<DocumentsListScreen> {
  String _textFilter = '';
  final _searchController = TextEditingController();
  bool _fabOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);
    final theme = Theme.of(context);

    final body = Stack(
        children: [
          Column(
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
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _fabOpen = false),
                child: Container(color: Colors.black54),
              ),
            ),
        ],
      );

    if (widget.embedded) {
      return Scaffold(body: body, floatingActionButton: _buildSpeedDial(context));
    }

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
      body: body,
      floatingActionButton: _buildSpeedDial(context),
    );
  }

  Widget _buildSpeedDial(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabOpen) ...[
          _SpeedDialItem(
            icon: Icons.insert_drive_file,
            label: 'Add Document',
            onTap: () {
              setState(() => _fabOpen = false);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DocumentFormScreen()),
              );
            },
            theme: theme,
          ),
          const SizedBox(height: 12),
          _SpeedDialItem(
            icon: Icons.folder_open,
            label: 'Map Directory',
            onTap: () {
              setState(() => _fabOpen = false);
              _pickAndImportDirectory();
            },
            theme: theme,
          ),
          const SizedBox(height: 12),
          _SpeedDialItem(
            icon: Icons.sync,
            label: 'Index All',
            iconColor: Colors.deepPurple,
            onTap: () {
              setState(() => _fabOpen = false);
              _indexAllDocuments();
            },
            theme: theme,
          ),
          const SizedBox(height: 16),
        ],
        FloatingActionButton(
          onPressed: () => setState(() => _fabOpen = !_fabOpen),
          child: AnimatedRotation(
            turns: _fabOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.menu_open, size: 28),
          ),
        ),
      ],
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
    try {
      // Force re-index by clearing hash
      final freshDoc = doc.copyWith(
        contentHash: '',
        clearLastIndexedAt: true,
      );
      await ref.read(embeddingIndexProvider.notifier).indexDocument(freshDoc);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${doc.title}" re-indexed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to index "${doc.title}": $e'),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
    }
  }

  Future<void> _pickAndImportDirectory() async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select directory to map',
    );

    if (dirPath == null || !mounted) return;

    // Show scanning indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Scanning ${p.basename(dirPath)}...'),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );

    // Scan directory
    final scanResult = await DocumentService.scanDirectory(dirPath);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (scanResult.supportedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No supported files found in ${p.basename(dirPath)}.\n'
            '${scanResult.skippedCount} files skipped.',
          ),
        ),
      );
      return;
    }

    // Show confirmation dialog with scan results
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DirectoryImportDialog(
        dirPath: dirPath,
        scanResult: scanResult,
      ),
    );

    if (confirmed != true || !mounted) return;

    // Get existing file paths to avoid duplicates
    final existingDocs = ref.read(documentsProvider).valueOrNull ?? [];
    final existingPaths = existingDocs.map((d) => d.filePath).toSet();

    // Import files
    final actions = ref.read(documentActionsProvider);
    final embeddingNotifier = ref.read(embeddingIndexProvider.notifier);
    var indexed = 0;
    var duplicates = 0;
    var errors = 0;

    // Show progress dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DirectoryProgressDialog(
        totalFiles: scanResult.supportedFiles.length,
        dirName: p.basename(dirPath),
      ),
    );

    for (final file in scanResult.supportedFiles) {
      if (!mounted) break;

      // Skip duplicates
      if (existingPaths.contains(file.path)) {
        duplicates++;
        // Update progress
        _updateProgressDialog(indexed + duplicates + errors,
            scanResult.supportedFiles.length);
        continue;
      }

      try {
        final fileName = p.basename(file.path);
        final dotIndex = fileName.lastIndexOf('.');
        final title = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
        final fileType = DocumentService.detectFileType(file.path);

        final doc = Document(
          id: '',
          title: title,
          filePath: file.path,
          fileType: fileType,
          tags: 'dir:${p.basename(dirPath)}',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final docId = await actions.addDocument(doc);
        final docWithId = doc.copyWith(id: docId);
        await embeddingNotifier.indexDocument(docWithId);

        indexed++;
        existingPaths.add(file.path);
      } catch (_) {
        errors++;
      }

      _updateProgressDialog(indexed + duplicates + errors,
          scanResult.supportedFiles.length);
    }

    // Dismiss progress dialog
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    // Show results
    if (mounted) {
      final resultParts = <String>[];
      resultParts.add('$indexed indexed');
      if (duplicates > 0) resultParts.add('$duplicates already existed');
      if (errors > 0) resultParts.add('$errors failed');
      if (scanResult.skippedCount > 0) {
        resultParts.add('${scanResult.skippedCount} unsupported skipped');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                errors > 0 ? Icons.warning_amber : Icons.check_circle,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${p.basename(dirPath)}: ${resultParts.join(" \u2022 ")}',
                ),
              ),
            ],
          ),
          backgroundColor: errors > 0 ? Colors.orange.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _updateProgressDialog(int current, int total) {
    // The progress dialog rebuilds via its own state
    _progressNotifier.value = current;
  }

  Future<void> _indexAllDocuments() async {
    var docs = ref.read(documentsProvider).valueOrNull ?? [];
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No documents to index.')),
      );
      return;
    }

    final embeddingNotifier = ref.read(embeddingIndexProvider.notifier);
    final actions = ref.read(documentActionsProvider);
    var indexed = 0;
    var failed = 0;
    var added = 0;
    var removed = 0;
    // skippedNotFound tracked via 'failed' counter
    String? lastError;
    final progressNotifier = ValueNotifier<String>('Scanning mapped directories...');

    // Show progress dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return ValueListenableBuilder<String>(
          valueListenable: progressNotifier,
          builder: (context, status, _) {
            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Re-indexing All Documents',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // ── Step 1: Re-scan mapped directories for new/removed files ──

    // Find all unique mapped root directories.
    // Documents from directory mapping have tags like "dir:FolderName".
    // We extract the dir tag, then walk up each doc's file path to find
    // the root directory whose basename matches the tag.
    final existingPaths = <String>{};
    final mappedRoots = <String, String>{}; // rootPath → dirTag

    for (final doc in docs) {
      existingPaths.add(doc.filePath);

      // Extract dir:XYZ tag
      final tags = doc.tags.split(',').map((t) => t.trim());
      for (final tag in tags) {
        if (tag.startsWith('dir:')) {
          final dirName = tag.substring(4);
          // Walk up from file to find the root with matching name
          var dir = p.dirname(doc.filePath);
          while (dir != p.dirname(dir)) {
            if (p.basename(dir) == dirName) {
              mappedRoots[dir] = tag;
              break;
            }
            dir = p.dirname(dir);
          }
          break; // Only need first dir: tag
        }
      }
    }

    // Scan each mapped root directory for new files
    for (final entry in mappedRoots.entries) {
      if (!mounted) break;
      final rootPath = entry.key;
      final dirTag = entry.value;
      final dirName = p.basename(rootPath);

      progressNotifier.value = 'Scanning $dirName...';

      try {
        final scanResult =
            await DocumentService.scanDirectory(rootPath);

        for (final file in scanResult.supportedFiles) {
          if (existingPaths.contains(file.path)) continue;

          // New file found — add it
          final fileName = p.basename(file.path);
          final dotIndex = fileName.lastIndexOf('.');
          final title =
              dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
          final fileType = DocumentService.detectFileType(file.path);

          final newDoc = Document(
            id: '',
            title: title,
            filePath: file.path,
            fileType: fileType,
            tags: dirTag,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );

          final docId = await actions.addDocument(newDoc);
          existingPaths.add(file.path);
          added++;

          // Add to docs list so it gets indexed below
          docs = [...docs, newDoc.copyWith(id: docId)];
        }
      } catch (_) {
        // Directory may have been deleted or is inaccessible
      }
    }

    // ── Step 2: Remove docs whose files no longer exist on disk ──

    progressNotifier.value = 'Checking for removed files...';
    final docsToRemove = <Document>[];

    for (final doc in docs) {
      if (!mounted) break;
      final file = File(doc.filePath);
      if (!await file.exists()) {
        docsToRemove.add(doc);
      }
    }

    for (final doc in docsToRemove) {
      if (!mounted) break;
      try {
        await embeddingNotifier.removeDocument(doc.id);
        await actions.deleteDocument(doc.id);
        removed++;
      } catch (_) {}
    }

    // Remove deleted docs from our working list
    final removedIds = docsToRemove.map((d) => d.id).toSet();
    docs = docs.where((d) => !removedIds.contains(d.id)).toList();

    // ── Step 3: Clear embeddings and re-index all documents ──

    progressNotifier.value = 'Clearing old embeddings...';
    final total = docs.length;

    for (final doc in docs) {
      if (!mounted) break;
      try {
        await embeddingNotifier.removeDocument(doc.id);
      } catch (_) {}
    }

    // Re-index each document — pass with cleared hash/timestamp
    // so indexDocument doesn't skip unchanged content
    for (var i = 0; i < docs.length; i++) {
      if (!mounted) break;
      final doc = docs[i];
      progressNotifier.value =
          'Indexing ${i + 1}/$total\n${doc.title}';
      try {
        // Clear contentHash and lastIndexedAt on the in-memory object
        // so indexDocument won't skip it as "unchanged"
        final freshDoc = doc.copyWith(
          contentHash: '',
          clearLastIndexedAt: true,
        );
        await embeddingNotifier.indexDocument(freshDoc);
        indexed++;
      } catch (e) {
        failed++;
        lastError = e.toString();
        debugPrint('Index failed for "${doc.title}": $e');
      }
    }

    progressNotifier.dispose();

    // Dismiss progress dialog
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (mounted) {
      final parts = <String>['$indexed indexed'];
      if (added > 0) parts.add('$added new');
      if (removed > 0) parts.add('$removed removed');
      if (failed > 0) parts.add('$failed failed');

      final message = parts.join(' \u2022 ');
      final hasErrors = failed > 0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasErrors ? Icons.warning_amber : Icons.check_circle,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(message)),
                ],
              ),
              if (hasErrors && lastError != null) ...[
                const SizedBox(height: 4),
                Text(
                  lastError,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          backgroundColor:
              hasErrors ? Colors.orange.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: hasErrors ? 8 : 5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  final ValueNotifier<int> _progressNotifier = ValueNotifier<int>(0);
}

/// Speed dial menu item for documents screen
class _SpeedDialItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ThemeData theme;
  final Color? iconColor;

  const _SpeedDialItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.theme,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onTap,
          backgroundColor: iconColor,
          child: Icon(icon,
              color: iconColor != null ? Colors.white : null),
        ),
      ],
    );
  }
}

/// Dialog showing directory scan results and asking for confirmation
class _DirectoryImportDialog extends StatelessWidget {
  final String dirPath;
  final DirectoryScanResult scanResult;

  const _DirectoryImportDialog({
    required this.dirPath,
    required this.scanResult,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group supported files by extension
    final extCounts = <String, int>{};
    for (final file in scanResult.supportedFiles) {
      final ext = p.extension(file.path).toLowerCase();
      extCounts[ext] = (extCounts[ext] ?? 0) + 1;
    }

    return AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.folder_open,
          color: Colors.deepPurple,
          size: 32,
        ),
      ),
      title: const Text('Map Directory'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder, size: 18,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dirPath,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${scanResult.supportedFiles.length} supported files found:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: extCounts.entries.map((e) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${e.key} (${e.value})',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (scanResult.skippedCount > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${scanResult.skippedCount} unsupported files will be skipped'
                      '${scanResult.skippedExtensions.isNotEmpty ? ' (${scanResult.skippedExtensions.take(5).join(", ")})' : ''}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Each file will be chunked and indexed for AI retrieval. '
              'Duplicate files already in your library will be skipped.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.download, size: 18),
          label: Text('Index ${scanResult.supportedFiles.length} Files'),
        ),
      ],
    );
  }
}

/// Progress dialog shown during directory import
class _DirectoryProgressDialog extends StatefulWidget {
  final int totalFiles;
  final String dirName;

  const _DirectoryProgressDialog({
    required this.totalFiles,
    required this.dirName,
  });

  @override
  State<_DirectoryProgressDialog> createState() =>
      _DirectoryProgressDialogState();
}

class _DirectoryProgressDialogState extends State<_DirectoryProgressDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Indexing ${widget.dirName}...',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Processing ${widget.totalFiles} files.\nThis may take a while for large directories.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
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
