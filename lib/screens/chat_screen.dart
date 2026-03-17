import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/ai_provider.dart';
import '../services/ai_service.dart';
import '../widgets/markdown_response.dart';

/// Full-screen chat interface ("Focus Mode").
/// Shares the same [aiChatProvider] state as the home-screen widget,
/// so the conversation is seamless when entering/leaving.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(aiChatProvider.notifier).sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(aiChatProvider);
    final theme = Theme.of(context);

    ref.listen(aiChatProvider, (prev, next) {
      if (prev != null && next.messages.length > prev.messages.length) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_fullscreen),
          tooltip: 'Exit focus mode',
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('AI Chat'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                ref.watch(aiServiceProvider).model,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => ref.read(aiChatProvider.notifier).newChat(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Chat'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: chatState.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 48,
                          color: theme.colorScheme.primary.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ask AI anything',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Search your vault, documents, and notes — or just chat.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      return _FocusChatBubble(
                        message: chatState.messages[index],
                      );
                    },
                  ),
          ),

          // Typing indicator
          if (chatState.isProcessing)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Thinking...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          // Error
          if (chatState.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  chatState.error!,
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

          // Input bar
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.of(context).viewPadding.bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        onSubmitted: (_) => _send(),
                        textInputAction: TextInputAction.send,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Message AI...',
                          prefixIcon:
                              const Icon(Icons.auto_awesome, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          filled: true,
                          fillColor: theme
                              .colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed:
                          _controller.text.trim().isNotEmpty &&
                                  !chatState.isProcessing
                              ? _send
                              : null,
                      icon: const Icon(Icons.send, size: 22),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen chat bubble — slightly larger and more spacious than the widget version.
class _FocusChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _FocusChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4, left: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            message.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    // Assistant message
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4, right: 48),
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownResponse(data: message.text),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _AiStatusBadge(aiOnline: message.aiOnline),
                    if (message.ragUsed)
                      _RagSourceBadge(sources: message.ragSources),
                  ],
                ),
              ],
            ),
          ),

          // Matched vault entries / notes
          if (message.matchedEntries.isNotEmpty ||
              message.matchedNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  ...message.matchedEntries.map((entry) {
                    return _SecretEntryCard(entry: entry);
                  }),
                  ...message.matchedNotes.map((note) {
                    return _NoteCard(note: note);
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AiStatusBadge extends StatelessWidget {
  final bool aiOnline;

  const _AiStatusBadge({required this.aiOnline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: aiOnline
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            aiOnline ? Icons.auto_awesome : Icons.search,
            size: 10,
            color: aiOnline ? Colors.green.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 3),
          Text(
            aiOnline ? 'AI' : 'Local',
            style: theme.textTheme.labelSmall?.copyWith(
              color: aiOnline ? Colors.green.shade700 : Colors.orange.shade700,
              fontWeight: FontWeight.w500,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _RagSourceBadge extends StatelessWidget {
  final List<String> sources;

  const _RagSourceBadge({required this.sources});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = sources.isNotEmpty
        ? 'RAG: ${sources.join(', ')}'
        : 'RAG search';
    return Tooltip(
      message: 'Retrieval-Augmented Generation was used to find relevant context',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.deepPurple,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.hub,
              size: 10,
              color: Colors.white,
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                text,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;

  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr =
        '${note.updatedAt.year}-${note.updatedAt.month.toString().padLeft(2, '0')}-${note.updatedAt.day.toString().padLeft(2, '0')}';
    final preview = note.body.isNotEmpty
        ? note.body.length > 200
            ? '${note.body.substring(0, 200)}...'
            : note.body
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.note, size: 16, color: theme.colorScheme.onSurface),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  note.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Note',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                preview,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            dateStr,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }
}

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
          Row(
            children: [
              Icon(
                _categoryIcon(entry.category ?? ''),
                size: 16,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.title ?? 'Untitled',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if ((entry.category ?? '').isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry.category,
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if ((entry.username as String? ?? '').isNotEmpty)
            _metaRow(context, 'User', entry.username),
          if ((entry.url as String? ?? '').isNotEmpty)
            _metaRow(context, 'URL', entry.url),
          if (entry.expiresAt != null) _expiryRow(context, entry),
          if (hasSecret) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _secretVisible ? secret : '\u2022' * 16,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () =>
                        setState(() => _secretVisible = !_secretVisible),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _secretVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: secret));
                      setState(() => _copied = true);
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _copied = false);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _copied ? Icons.check : Icons.copy,
                        size: 16,
                        color: _copied
                            ? Colors.green
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 8),
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

    if (isExpired) {
      statusColor = theme.colorScheme.error;
      statusText = '$dateStr  EXPIRED';
    } else if (isExpiringSoon) {
      statusColor = Colors.orange;
      statusText = '$dateStr  Expiring soon';
    } else {
      statusColor = theme.colorScheme.onSurfaceVariant;
      statusText = dateStr;
    }

    return _metaRow(context, 'Expires', statusText,
        valueColor: (isExpired || isExpiringSoon) ? statusColor : null);
  }

  Widget _metaRow(BuildContext context, String label, String value,
      {Color? valueColor}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 55,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: valueColor,
                fontWeight: valueColor != null ? FontWeight.bold : null,
              ),
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
      case 'ssh key':
        return Icons.terminal;
      default:
        return Icons.lock;
    }
  }
}
