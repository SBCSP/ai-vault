import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vault_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';

class NoteFormScreen extends ConsumerStatefulWidget {
  final VaultEntry? entry;

  const NoteFormScreen({super.key, this.entry});

  @override
  ConsumerState<NoteFormScreen> createState() => _NoteFormScreenState();
}

class _NoteFormScreenState extends ConsumerState<NoteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _tagsController;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleController = TextEditingController(text: e?.title ?? '');
    _bodyController = TextEditingController(text: e?.notes ?? '');
    _tagsController = TextEditingController(text: e?.tags ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Note' : 'New Note'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
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
                  TextFormField(
                    controller: _bodyController,
                    decoration: InputDecoration(
                      labelText: 'Note',
                      hintText: 'Write your note here...',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                    ),
                    maxLines: null,
                    minLines: 15,
                    keyboardType: TextInputType.multiline,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Tags (comma-separated)',
                      prefixIcon: Icon(Icons.tag),
                      border: OutlineInputBorder(),
                      hintText: 'e.g. meeting, ideas, todo',
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 16),
                  // Word/character count
                  Text(
                    '${_bodyController.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} words  •  ${_bodyController.text.length} characters',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final actions = ref.read(vaultActionsProvider);
    final now = DateTime.now();

    final entry = VaultEntry(
      id: widget.entry?.id ?? '',
      title: _titleController.text.trim(),
      username: '',
      password: '',
      url: '',
      notes: _bodyController.text,
      category: 'Note',
      tags: _tagsController.text.trim(),
      createdAt: widget.entry?.createdAt ?? now,
      updatedAt: now,
    );

    if (_isEditing) {
      await actions.updateEntry(entry);
    } else {
      await actions.addEntry(entry);
    }

    if (mounted) Navigator.pop(context);
  }
}
