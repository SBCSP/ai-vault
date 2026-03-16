import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vault_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/embedding_provider.dart';
import '../providers/vault_provider.dart';

class EntryFormScreen extends ConsumerStatefulWidget {
  final VaultEntry? entry;

  const EntryFormScreen({super.key, this.entry});

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _urlController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;
  late String _category;
  bool _obscurePassword = true;
  bool _obscurePrivateKey = true;
  DateTime? _expiresAt;

  bool get _isEditing => widget.entry != null;
  bool get _isSshKey => _category.toLowerCase() == 'ssh key';

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleController = TextEditingController(text: e?.title ?? '');
    _usernameController = TextEditingController(text: e?.username ?? '');
    _passwordController = TextEditingController(text: e?.password ?? '');
    _urlController = TextEditingController(text: e?.url ?? '');
    _notesController = TextEditingController(text: e?.notes ?? '');
    _tagsController = TextEditingController(text: e?.tags ?? '');
    _category = e?.category ?? 'General';
    _expiresAt = e?.expiresAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 10)),
      helpText: 'Select expiry date',
    );
    if (picked != null) {
      setState(() => _expiresAt = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Entry' : 'New Entry'),
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
            constraints: const BoxConstraints(maxWidth: 600),
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
                  ),
                  const SizedBox(height: 16),
                  _CategoryDropdown(
                    value: _category,
                    onChanged: (v) => setState(() => _category = v),
                  ),
                  // --- Category-specific fields ---
                  if (_isSshKey) ...[
                    // SSH Key: Public Key + Private Key
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Public Key',
                        hintText: 'ssh-rsa AAAA...',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.vpn_key_outlined),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Private key: always multiline to preserve formatting.
                    // Hide/show by toggling between a masked overlay and
                    // the real editable field.
                    Stack(
                      children: [
                        // The actual editable field (always present so
                        // controller state is retained)
                        Opacity(
                          opacity: _obscurePrivateKey ? 0.0 : 1.0,
                          child: IgnorePointer(
                            ignoring: _obscurePrivateKey,
                            child: TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Private Key',
                                hintText:
                                    '-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----',
                                border: const OutlineInputBorder(),
                                alignLabelWithHint: true,
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.visibility_off),
                                  tooltip: 'Hide private key',
                                  onPressed: () => setState(
                                      () => _obscurePrivateKey = true),
                                ),
                              ),
                              maxLines: null,
                              minLines: 10,
                              keyboardType: TextInputType.multiline,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        // Masked overlay when hidden
                        if (_obscurePrivateKey)
                          GestureDetector(
                            onTap: () =>
                                setState(() => _obscurePrivateKey = false),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Private Key',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.visibility),
                                  tooltip: 'Show private key',
                                  onPressed: () => setState(
                                      () => _obscurePrivateKey = false),
                                ),
                              ),
                              child: Text(
                                _passwordController.text.isEmpty
                                    ? 'Tap to enter private key'
                                    : '\u2022' * 24,
                                style: TextStyle(
                                  color: _passwordController.text.isEmpty
                                      ? theme.colorScheme.onSurfaceVariant
                                      : null,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ] else ...[
                    // Default: Username + Password + URL
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username / Email',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password / Secret',
                        prefixIcon: const Icon(Icons.key),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'URL / Service',
                        prefixIcon: Icon(Icons.link),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Expiry date picker
                  InkWell(
                    onTap: _pickExpiryDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Expiry Date',
                        prefixIcon: Icon(
                          Icons.event,
                          color: _expiresAt != null &&
                                  _expiresAt!.isBefore(DateTime.now())
                              ? theme.colorScheme.error
                              : null,
                        ),
                        border: const OutlineInputBorder(),
                        suffixIcon: _expiresAt != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Clear expiry date',
                                onPressed: () {
                                  setState(() => _expiresAt = null);
                                },
                              )
                            : const Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        _expiresAt != null
                            ? _formatDate(_expiresAt!)
                            : 'No expiry date set',
                        style: TextStyle(
                          color: _expiresAt == null
                              ? theme.colorScheme.onSurfaceVariant
                              : _expiresAt!.isBefore(DateTime.now())
                                  ? theme.colorScheme.error
                                  : null,
                        ),
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
                      hintText: 'e.g. work, cloud, production',
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: Icon(Icons.notes),
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
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
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      url: _urlController.text.trim(),
      notes: _notesController.text.trim(),
      category: _category,
      tags: _tagsController.text.trim(),
      createdAt: widget.entry?.createdAt ?? now,
      updatedAt: now,
      expiresAt: _expiresAt,
    );

    if (_isEditing) {
      await actions.updateEntry(entry);
    } else {
      await actions.addEntry(entry);
    }

    // Fire-and-forget: update embedding index
    ref.read(embeddingIndexProvider.notifier).indexEntry(entry);

    if (mounted) Navigator.pop(context);
  }
}

/// Category dropdown with an "Add new..." option
class _CategoryDropdown extends ConsumerWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _CategoryDropdown({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryProvider);

    // Make sure the current value is in the list
    final items = categories.contains(value)
        ? categories
        : [value, ...categories];

    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Category',
        prefixIcon: Icon(Icons.category),
        border: OutlineInputBorder(),
      ),
      items: [
        ...items.map(
          (c) => DropdownMenuItem(value: c, child: Text(c)),
        ),
        const DropdownMenuItem(
          value: '__add_new__',
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('Add new category...'),
            ],
          ),
        ),
      ],
      onChanged: (v) {
        if (v == '__add_new__') {
          _showAddCategoryDialog(context, ref);
        } else if (v != null) {
          onChanged(v);
        }
      },
    );
  }

  Future<void> _showAddCategoryDialog(
      BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('New Category'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Category name',
              hintText: 'e.g. Database, Cloud, Certificate',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      await ref.read(categoryProvider.notifier).addCategory(result);
      onChanged(result);
    }
  }
}
