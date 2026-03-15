import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../services/ai_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _modelController;
  bool _testing = false;
  OllamaStatus? _connectionResult;

  @override
  void initState() {
    super.initState();
    final aiService = ref.read(aiServiceProvider);
    _urlController = TextEditingController(text: aiService.serverUrl);
    _modelController = TextEditingController(text: aiService.model);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'AI Configuration',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(
                            labelText: 'Ollama Server URL',
                            hintText: 'http://localhost:11434',
                            prefixIcon: Icon(Icons.dns),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            ref
                                .read(aiServiceProvider.notifier)
                                .updateServerUrl(value);
                            setState(() => _connectionResult = null);
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _modelController,
                          decoration: const InputDecoration(
                            labelText: 'Model Name',
                            hintText: 'gemma3:1b',
                            prefixIcon: Icon(Icons.psychology),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            ref
                                .read(aiServiceProvider.notifier)
                                .updateModel(value);
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: _testing ? null : _testConnection,
                              icon: _testing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.wifi_find),
                              label: const Text('Test Connection'),
                            ),
                            const SizedBox(width: 12),
                            if (_connectionResult != null)
                              _buildStatusBadge(theme),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _CategoriesCard(),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.help_outline,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Quick Start',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'To use AI search, you need Ollama installed '
                          'and running with the Gemma 3 1B model:',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            '# Install Ollama from https://ollama.com\n\n'
                            '# Pull and run the Gemma 3 1B model:\n'
                            'ollama run gemma3:1b\n\n'
                            '# Ollama runs on http://localhost:11434\n'
                            '# The server starts automatically on install.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ThemeData theme) {
    final status = _connectionResult!.status;

    final Color color;
    final IconData icon;
    final String text;

    switch (status) {
      case OllamaConnectionStatus.ready:
        color = Colors.green;
        icon = Icons.check_circle;
        text = 'Ready';
      case OllamaConnectionStatus.ollamaNotRunning:
        color = theme.colorScheme.error;
        icon = Icons.error;
        text = 'Ollama not running';
      case OllamaConnectionStatus.modelNotFound:
        color = Colors.orange;
        icon = Icons.warning;
        text = 'Model not found';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _connectionResult = null;
    });

    final result = await ref.read(aiServiceProvider).checkStatus();

    if (mounted) {
      setState(() {
        _testing = false;
        _connectionResult = result;
      });
    }
  }
}

class _CategoriesCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoryProvider);
    final notifier = ref.read(categoryProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.category, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Categories',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showAddDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.map((cat) {
                final isDefault = notifier.isDefault(cat);
                return Chip(
                  label: Text(cat),
                  avatar: Icon(
                    isDefault ? Icons.lock_outline : Icons.label,
                    size: 16,
                  ),
                  deleteIcon: isDefault
                      ? null
                      : const Icon(Icons.close, size: 16),
                  onDeleted: isDefault
                      ? null
                      : () => _confirmDelete(context, ref, cat),
                  backgroundColor: isDefault
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.tertiaryContainer,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'Default categories cannot be removed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
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
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, String category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Category'),
        content: Text(
          'Remove "$category"? Existing entries with this category will keep it, but it won\'t appear in the dropdown anymore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(categoryProvider.notifier).removeCategory(category);
    }
  }
}
