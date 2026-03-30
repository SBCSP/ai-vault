import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_session.dart';
import '../providers/ai_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_history_provider.dart';
import '../providers/embedding_provider.dart';
import '../providers/shell_navigation_provider.dart';
import 'chat_screen.dart';

class ChatHistoryScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const ChatHistoryScreen({super.key, this.embedded = false});

  @override
  ConsumerState<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends ConsumerState<ChatHistoryScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionsAsync = ref.watch(chatSessionsProvider);

    final body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search chats...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: sessionsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (sessions) {
                final filtered = _filter.isEmpty
                    ? sessions
                    : sessions.where((s) {
                        return s.title.toLowerCase().contains(_filter) ||
                            s.preview.toLowerCase().contains(_filter);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          sessions.isEmpty
                              ? 'No saved chats yet'
                              : 'No chats match your search',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (sessions.isEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Save a chat from the chat screen to see it here',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final session = filtered[index];
                    return _ChatSessionTile(
                      session: session,
                      onTap: () => _openSession(session),
                      onDelete: () => _confirmDelete(session),
                    );
                  },
                );
              },
            ),
          ),
        ],
      );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      body: body,
    );
  }

  void _openSession(ChatSession session) {
    ref.read(aiChatProvider.notifier).loadSession(session);
    if (widget.embedded) {
      ref.read(shellNavigationProvider.notifier).state = 1; // AI Chat
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      );
    }
  }

  Future<void> _confirmDelete(ChatSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat?'),
        content: Text(
          'Delete "${session.title}"? This will also remove its embeddings from the index.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final actions = ref.read(chatSessionActionsProvider);
      await ref.read(embeddingIndexProvider.notifier)
          .removeChatSession(session.id);
      await actions.deleteSession(session.id);
    }
  }
}

class _ChatSessionTile extends StatelessWidget {
  final ChatSession session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChatSessionTile({
    required this.session,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr =
        '${session.updatedAt.year}-${session.updatedAt.month.toString().padLeft(2, '0')}-${session.updatedAt.day.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.chat_bubble_outline,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (session.isIndexed)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.hub, size: 9,
                                    color: Colors.white),
                                SizedBox(width: 2),
                                Text(
                                  'Indexed',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.preview,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dateStr  \u2022  ${session.userMessageCount} messages',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete chat',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
