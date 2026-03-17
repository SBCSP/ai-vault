import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_session.dart';
import '../models/note.dart';
import '../providers/ai_provider.dart';
import '../providers/chat_history_provider.dart';
import '../providers/embedding_provider.dart';
import '../screens/chat_history_screen.dart';
import '../screens/chat_screen.dart';
import '../services/ai_service.dart';
import 'markdown_response.dart';

class AiChatWidget extends ConsumerStatefulWidget {
  const AiChatWidget({super.key});

  @override
  ConsumerState<AiChatWidget> createState() => _AiChatWidgetState();
}

class _AiChatWidgetState extends ConsumerState<AiChatWidget> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(aiChatProvider.notifier).sendMessage(text);
    // Scroll to bottom after sending
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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

  Future<void> _showSaveDialog() async {
    final chatState = ref.read(aiChatProvider);
    if (chatState.messages.isEmpty) return;

    final firstUser = chatState.messages.where((m) => m.isUser).firstOrNull;
    final autoTitle = firstUser != null
        ? (firstUser.text.length > 50
            ? '${firstUser.text.substring(0, 50)}...'
            : firstUser.text)
        : 'Chat ${DateTime.now().toString().substring(0, 16)}';

    final titleController = TextEditingController(text: autoTitle);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.shield, color: Colors.deepPurple, size: 32),
        ),
        title: const Text('Save & Index Chat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This chat will be saved to your history and indexed for AI retrieval.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Chat Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.title),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.shield, size: 18),
            label: const Text('Save & Index'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final title = titleController.text.trim().isEmpty
          ? autoTitle
          : titleController.text.trim();
      await _saveAndIndexChat(title);
    }
    titleController.dispose();
  }

  Future<void> _saveAndIndexChat(String title) async {
    final chatState = ref.read(aiChatProvider);
    final actions = ref.read(chatSessionActionsProvider);

    final sessionId = await actions.saveSession(title, chatState.messages);
    await actions.markIndexed(sessionId);

    final now = DateTime.now();
    final sessionMessages = chatState.messages
        .map((m) => ChatSessionMessage(
              text: m.text,
              isUser: m.isUser,
              timestamp: now,
            ))
        .toList();

    final session = ChatSession(
      id: sessionId,
      title: title,
      messages: sessionMessages,
      isIndexed: true,
      createdAt: now,
      updatedAt: now,
    );

    await ref.read(embeddingIndexProvider.notifier).indexChatSession(session);
    ref.read(aiChatProvider.notifier).markSaved(sessionId, title);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.shield, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Chat "$title" saved & indexed')),
            ],
          ),
          backgroundColor: Colors.deepPurple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _showNewChatDialog() async {
    final chatState = ref.read(aiChatProvider);

    if (chatState.messages.isEmpty || chatState.loadedSessionId != null) {
      ref.read(aiChatProvider.notifier).newChat();
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.shield, color: Colors.deepPurple, size: 32),
        ),
        title: const Text('Save this chat?'),
        content: const Text(
          'Would you like to save and index this conversation before starting a new chat?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(
              'Discard',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'save'),
            icon: const Icon(Icons.shield, size: 18),
            label: const Text('Save & Index'),
          ),
        ],
      ),
    );

    if (result == 'save') {
      await _showSaveDialog();
      if (mounted) {
        ref.read(aiChatProvider.notifier).newChat();
      }
    } else if (result == 'discard') {
      ref.read(aiChatProvider.notifier).newChat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(aiChatProvider);
    final theme = Theme.of(context);

    // Auto-scroll when new messages arrive
    ref.listen(aiChatProvider, (prev, next) {
      if (prev != null && next.messages.length > prev.messages.length) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    final hasMessages = chatState.messages.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with "New Chat" button
        if (hasMessages)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AI Chat',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        ref.watch(aiServiceProvider).model,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ChatHistoryScreen()),
                      ),
                      icon: const Icon(Icons.history, size: 18),
                      tooltip: 'Chat History',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ChatScreen()),
                      ),
                      icon: const Icon(Icons.open_in_full, size: 18),
                      tooltip: 'Focus mode',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: chatState.messages.isNotEmpty
                          ? () => _showNewChatDialog()
                          : null,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New Chat'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // Messages list
        if (hasMessages)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              itemCount: chatState.messages.length,
              itemBuilder: (context, index) {
                final msg = chatState.messages[index];
                return _ChatBubble(message: msg);
              },
            ),
          ),

        // Typing indicator
        if (chatState.isProcessing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Thinking...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

        // Error display
        if (chatState.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                chatState.error!,
                style: TextStyle(
                  color: theme.colorScheme.onErrorContainer,
                  fontSize: 12,
                ),
              ),
            ),
          ),

        // Input field
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: (_) => _send(),
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: hasMessages
                        ? 'Continue the conversation...'
                        : 'Ask AI anything...',
                    prefixIcon: const Icon(Icons.auto_awesome, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (!hasMessages) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ChatScreen()),
                  ),
                  icon: const Icon(Icons.open_in_full, size: 18),
                  tooltip: 'Focus mode',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(40, 40),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton.filled(
                onPressed: _controller.text.trim().isNotEmpty && !chatState.isProcessing
                    ? _send
                    : null,
                icon: const Icon(Icons.send, size: 20),
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A single chat message bubble
class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 6, bottom: 2, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            message.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      );
    }

    // Assistant message
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 2, right: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text response
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
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

          // Matched entries (if vault result)
          if (message.matchedEntries.isNotEmpty ||
              message.matchedNotes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
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

/// Small badge showing whether the response is AI-powered or local fallback
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
              color:
                  aiOnline ? Colors.green.shade700 : Colors.orange.shade700,
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
      message:
          'Retrieval-Augmented Generation was used to find relevant context',
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

/// Card for displaying a matched note in AI search results
class _NoteCard extends StatelessWidget {
  final Note note;

  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr =
        '${note.updatedAt.year}-${note.updatedAt.month.toString().padLeft(2, '0')}-${note.updatedAt.day.toString().padLeft(2, '0')}';

    // Show first few lines of body as preview
    final preview = note.body.isNotEmpty
        ? note.body.length > 150
            ? '${note.body.substring(0, 150)}...'
            : note.body
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                preview,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                maxLines: 4,
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
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + category
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

          // Metadata
          if ((entry.username as String? ?? '').isNotEmpty)
            _metaRow(context, 'User', entry.username),
          if ((entry.url as String? ?? '').isNotEmpty)
            _metaRow(context, 'URL', entry.url),

          // Expiry
          if (entry.expiresAt != null) _expiryRow(context, entry),

          // Secret with copy button
          if (hasSecret) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
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

    return _metaRow(
      context,
      'Expires',
      statusText,
      valueColor: (isExpired || isExpiringSoon) ? statusColor : null,
    );
  }

  Widget _metaRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
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
