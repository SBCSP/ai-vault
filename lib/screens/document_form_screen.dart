import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/document.dart';
import '../providers/auth_provider.dart';
import '../providers/documents_provider.dart';
import '../providers/embedding_provider.dart';
import '../services/document_service.dart';

class DocumentFormScreen extends ConsumerStatefulWidget {
  final Document? document;

  const DocumentFormScreen({super.key, this.document});

  @override
  ConsumerState<DocumentFormScreen> createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends ConsumerState<DocumentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _tagsController;
  String? _filePath;
  String _fileType = 'txt';
  bool _saving = false;
  int? _fileSize;

  bool get _isEditing => widget.document != null;

  @override
  void initState() {
    super.initState();
    final d = widget.document;
    _titleController = TextEditingController(text: d?.title ?? '');
    _tagsController = TextEditingController(text: d?.tags ?? '');
    _filePath = d?.filePath;
    _fileType = d?.fileType ?? 'txt';
    if (_filePath != null) {
      _loadFileSize();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadFileSize() async {
    if (_filePath != null) {
      final size = await DocumentService.getFileSize(_filePath!);
      if (mounted) {
        setState(() => _fileSize = size);
      }
    }
  }

  static const _supportedExtensions = [
    '.txt', '.md', '.markdown', '.json', '.yaml', '.yml', '.csv', '.log', '.pdf',
  ];

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final ext = path.substring(path.lastIndexOf('.')).toLowerCase();

      if (!_supportedExtensions.contains(ext)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unsupported file type: $ext\nSupported: ${_supportedExtensions.join(", ")}'),
            ),
          );
        }
        return;
      }

      setState(() {
        _filePath = path;
        _fileType = DocumentService.detectFileType(path);
        _fileSize = result.files.single.size;
      });

      // Auto-fill title from filename if title is empty
      if (_titleController.text.isEmpty) {
        final fileName = path.split('/').last;
        // Remove extension
        final dotIndex = fileName.lastIndexOf('.');
        final name = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
        _titleController.text = name;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Document' : 'Add Document'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Indexing...' : 'Save & Index'),
          ),
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      prefixIcon: Icon(Icons.title),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Title is required' : null,
                    textInputAction: TextInputAction.next,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),

                  // File picker section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.folder_open,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'File',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_filePath != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme
                                    .colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.insert_drive_file,
                                        size: 16,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _filePath!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_fileSize != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          _fileType.toUpperCase(),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          DocumentService.formatFileSize(
                                              _fileSize!),
                                          style:
                                              theme.textTheme.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          FilledButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.file_open, size: 18),
                            label: Text(_filePath == null
                                ? 'Choose File'
                                : 'Change File'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Supported: .pdf, .txt, .md, .json, .yaml, .csv, .log',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Tags (comma-separated)',
                      prefixIcon: Icon(Icons.tag),
                      border: OutlineInputBorder(),
                      hintText: 'e.g. readme, docs, config',
                    ),
                    textInputAction: TextInputAction.done,
                  ),

                  if (_isEditing && widget.document != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: theme.colorScheme.primary,
                                    size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Index Info',
                                  style:
                                      theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Chunks: ${widget.document!.chunkCount}',
                              style: theme.textTheme.bodySmall,
                            ),
                            if (widget.document!.lastIndexedAt != null)
                              Text(
                                'Last indexed: ${_formatDate(widget.document!.lastIndexedAt!)}',
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file')),
      );
      return;
    }

    // Verify file exists
    final exists = await DocumentService.fileExists(_filePath!);
    if (!exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found on disk')),
        );
      }
      return;
    }

    setState(() => _saving = true);

    final actions = ref.read(documentActionsProvider);
    final now = DateTime.now();

    final doc = Document(
      id: widget.document?.id ?? '',
      title: _titleController.text.trim(),
      filePath: _filePath!,
      fileType: _fileType,
      chunkCount: widget.document?.chunkCount ?? 0,
      contentHash: widget.document?.contentHash ?? '',
      tags: _tagsController.text.trim(),
      createdAt: widget.document?.createdAt ?? now,
      updatedAt: now,
      lastIndexedAt: widget.document?.lastIndexedAt,
    );

    String docId;
    if (_isEditing) {
      await actions.updateDocument(doc);
      docId = doc.id;
    } else {
      docId = await actions.addDocument(doc);
    }

    // Index the document (read, chunk, embed)
    final docWithId = doc.copyWith(id: docId);
    await ref.read(embeddingIndexProvider.notifier).indexDocument(docWithId);

    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
    }
  }
}
