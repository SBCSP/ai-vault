import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoryProvider);
    final notifier = ref.read(categoryProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
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
                // Default categories section
                Text(
                  'Default Categories',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'These categories are built-in and cannot be removed.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: categories
                        .where((c) => notifier.isDefault(c))
                        .map((cat) => ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                                child: Icon(
                                  _categoryIcon(cat),
                                  color: theme.colorScheme.onSecondaryContainer,
                                  size: 20,
                                ),
                              ),
                              title: Text(cat),
                              trailing: Icon(
                                Icons.lock_outline,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // Custom categories section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Custom Categories',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _showAddDialog(context, ref),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final custom = categories
                        .where((c) => !notifier.isDefault(c))
                        .toList();

                    if (custom.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.category_outlined,
                                  size: 40,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No custom categories yet.\nTap "Add" to create one.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    return Card(
                      child: Column(
                        children: custom.map((cat) {
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.tertiaryContainer,
                              child: Icon(
                                Icons.label,
                                color: theme.colorScheme.onTertiaryContainer,
                                size: 20,
                              ),
                            ),
                            title: Text(cat),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: theme.colorScheme.error,
                              ),
                              tooltip: 'Remove category',
                              onPressed: () =>
                                  _confirmDelete(context, ref, cat),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'general':
        return Icons.lock;
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
        return Icons.label;
    }
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
