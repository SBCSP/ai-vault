import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_provider.dart';

class AiSearchBar extends ConsumerStatefulWidget {
  const AiSearchBar({super.key});

  @override
  ConsumerState<AiSearchBar> createState() => _AiSearchBarState();
}

class _AiSearchBarState extends ConsumerState<AiSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiSearch = ref.watch(aiSearchProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _controller,
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                ref.read(aiSearchProvider.notifier).search(value);
              }
            },
            decoration: InputDecoration(
              hintText: 'Ask AI to find a secret...',
              prefixIcon: const Icon(Icons.auto_awesome),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        ref.read(aiSearchProvider.notifier).clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (aiSearch.isSearching)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Text('Asking AI...'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    ref.watch(aiServiceProvider).model,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (aiSearch.result != null)
          _AiResponseCard(
            response: aiSearch.result!.response,
            matchedEntries: aiSearch.result!.matchedEntries,
            aiOnline: aiSearch.result!.aiOnline,
          ),
        if (aiSearch.error != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              aiSearch.error!,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
      ],
    );
  }
}

/// Rich AI response card with copyable secrets
class _AiResponseCard extends StatelessWidget {
  final String response;
  final List matchedEntries;
  final bool aiOnline;

  const _AiResponseCard({
    required this.response,
    required this.matchedEntries,
    required this.aiOnline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If we have matched entries, show rich cards with copy buttons
    if (matchedEntries.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI conversational response
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      response,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // AI status badge
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _AiStatusBadge(aiOnline: aiOnline),
            ),
            const Divider(height: 1),
            // Entry cards
            ...matchedEntries.map((entry) {
              return _SecretEntryCard(entry: entry);
            }),
          ],
        ),
      );
    }

    // Fallback: plain text response (no matches)
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  response,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AiStatusBadge(aiOnline: aiOnline),
        ],
      ),
    );
  }
}

/// Small badge showing whether the response is AI-powered or local fallback
class _AiStatusBadge extends StatelessWidget {
  final bool aiOnline;

  const _AiStatusBadge({required this.aiOnline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: aiOnline
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: aiOnline
              ? Colors.green.withValues(alpha: 0.4)
              : Colors.orange.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            aiOnline ? Icons.auto_awesome : Icons.search,
            size: 12,
            color: aiOnline ? Colors.green.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            aiOnline ? 'AI-powered response' : 'Local search (AI offline)',
            style: theme.textTheme.labelSmall?.copyWith(
              color: aiOnline ? Colors.green.shade700 : Colors.orange.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual entry card with copyable secret
class _SecretEntryCard extends StatefulWidget {
  final dynamic entry;

  const _SecretEntryCard({required this.entry});

  @override
  State<_SecretEntryCard> createState() => _SecretEntryCardState();
}

class _SecretEntryCardState extends State<_SecretEntryCard> {
  bool _secretVisible = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final secret = entry.password as String? ?? '';
    final hasSecret = secret.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + category
          Row(
            children: [
              Icon(
                _categoryIcon(entry.category ?? ''),
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.title ?? 'Untitled',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if ((entry.category ?? '').isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    entry.category,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Metadata
          if ((entry.username as String? ?? '').isNotEmpty)
            _metaRow(context, 'Username', entry.username),
          if ((entry.url as String? ?? '').isNotEmpty)
            _metaRow(context, 'URL', entry.url),

          // Updated date
          _metaRow(
            context,
            'Updated',
            '${entry.updatedAt.year}-${entry.updatedAt.month.toString().padLeft(2, '0')}-${entry.updatedAt.day.toString().padLeft(2, '0')}',
          ),

          // Expiry date
          if (entry.expiresAt != null) _expiryRow(context, entry),

          if ((entry.notes as String? ?? '').isNotEmpty)
            _metaRow(context, 'Notes', entry.notes),

          // Secret with copy button
          if (hasSecret) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _secretVisible ? secret : '\u2022' * 16,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _secretVisible
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 20,
                    ),
                    tooltip: _secretVisible ? 'Hide' : 'Show',
                    onPressed: () {
                      setState(() => _secretVisible = !_secretVisible);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: Icon(
                      _copied ? Icons.check : Icons.copy,
                      size: 20,
                      color: _copied ? Colors.green : null,
                    ),
                    tooltip: 'Copy to clipboard',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: secret));
                      setState(() => _copied = true);
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) {
                          setState(() => _copied = false);
                        }
                      });
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 4),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _expiryRow(BuildContext context, dynamic entry) {
    final theme = Theme.of(context);
    final expiresAt = entry.expiresAt as DateTime;
    final isExpired = expiresAt.isBefore(DateTime.now());
    final isExpiringSoon = !isExpired &&
        expiresAt.isBefore(DateTime.now().add(const Duration(days: 30)));
    final dateStr =
        '${expiresAt.year}-${expiresAt.month.toString().padLeft(2, '0')}-${expiresAt.day.toString().padLeft(2, '0')}';

    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    if (isExpired) {
      statusColor = theme.colorScheme.error;
      statusText = '$dateStr  EXPIRED';
      statusIcon = Icons.error;
    } else if (isExpiringSoon) {
      statusColor = Colors.orange;
      statusText = '$dateStr  Expiring soon';
      statusIcon = Icons.warning;
    } else {
      statusColor = theme.colorScheme.onSurfaceVariant;
      statusText = dateStr;
      statusIcon = Icons.event;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              'Expires',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: statusColor,
              fontWeight: isExpired || isExpiringSoon
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'api key':
        return Icons.key;
      case 'login':
        return Icons.login;
      case 'credit card':
        return Icons.credit_card;
      case 'note':
      case 'secure note':
        return Icons.note;
      case 'ssh key':
        return Icons.terminal;
      default:
        return Icons.lock;
    }
  }
}
