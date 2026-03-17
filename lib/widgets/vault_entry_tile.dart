import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/vault_entry.dart';

class VaultEntryTile extends StatelessWidget {
  final VaultEntry entry;
  final bool isHighlighted;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const VaultEntryTile({
    super.key,
    required this.entry,
    this.isHighlighted = false,
    required this.onTap,
    required this.onDelete,
  });

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'login':
        return Icons.login;
      case 'api key':
        return Icons.api;
      case 'credit card':
        return Icons.credit_card;
      case 'ssh key':
        return Icons.terminal;
      case 'wifi':
        return Icons.wifi;
      default:
        return Icons.lock;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await _showDeleteConfirmation(context, entry);
      },
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        elevation: isHighlighted ? 4 : 1,
        color: isHighlighted
            ? theme.colorScheme.primaryContainer
            : theme.cardColor,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: isHighlighted
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              _categoryIcon(entry.category),
              color: isHighlighted
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text(
            entry.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  if (entry.username.isNotEmpty) entry.username,
                  if (entry.url.isNotEmpty) entry.url,
                ].join(' \u2022 '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (entry.isExpired)
                Text(
                  'EXPIRED',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (entry.isExpiringSoon)
                const Text(
                  'Expiring soon',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.password.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy password',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: entry.password));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                tooltip: 'Delete',
                onPressed: () async {
                  final confirmed =
                      await _showDeleteConfirmation(context, entry);
                  if (confirmed == true) onDelete();
                },
              ),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  static Future<bool?> _showDeleteConfirmation(
      BuildContext context, VaultEntry entry) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteConfirmationDialog(entry: entry),
    );
  }
}

class _DeleteConfirmationDialog extends StatefulWidget {
  final VaultEntry entry;

  const _DeleteConfirmationDialog({required this.entry});

  @override
  State<_DeleteConfirmationDialog> createState() =>
      _DeleteConfirmationDialogState();
}

class _DeleteConfirmationDialogState
    extends State<_DeleteConfirmationDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final matches = _controller.text.trim() == widget.entry.title;
      if (matches != _matches) {
        setState(() => _matches = matches);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          const Text('Delete Forever'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This action cannot be undone. To confirm, type the name of the secret:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          // Copyable secret name
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    widget.entry.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy name',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: widget.entry.title));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Name copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Type secret name to confirm',
              border: const OutlineInputBorder(),
              errorText: _controller.text.isNotEmpty && !_matches
                  ? 'Name does not match'
                  : null,
            ),
            onSubmitted: (_) {
              if (_matches) Navigator.pop(context, true);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          icon: const Icon(Icons.delete_forever),
          label: const Text('Delete Forever'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            disabledBackgroundColor:
                theme.colorScheme.error.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }
}
