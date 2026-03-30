import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/embedding_provider.dart';
import '../providers/nav_visibility_provider.dart';
import '../providers/secrets_lock_provider.dart';
import '../providers/shell_navigation_provider.dart';
import '../providers/version_provider.dart';
import 'chat_history_screen.dart';
import 'chat_screen.dart';
import 'dashboard_content.dart';
import 'documents_list_screen.dart';
import 'ideas_list_screen.dart';
import 'notes_list_screen.dart';
import 'server_management_screen.dart';
import 'settings_screen.dart';
import 'vault_list_screen.dart';
import 'wiki_screen.dart';

/// Icon and selected icon for each nav destination, keyed by id.
const _navIcons = <int, (IconData, IconData)>{
  0: (Icons.dashboard_outlined, Icons.dashboard),
  1: (Icons.auto_awesome_outlined, Icons.auto_awesome),
  2: (Icons.shield_outlined, Icons.shield),
  3: (Icons.note_outlined, Icons.note),
  4: (Icons.lightbulb_outline, Icons.lightbulb),
  5: (Icons.description_outlined, Icons.description),
  6: (Icons.chat_bubble_outline, Icons.chat_bubble),
  7: (Icons.dns_outlined, Icons.dns),
  8: (Icons.menu_book_outlined, Icons.menu_book),
  9: (Icons.settings_outlined, Icons.settings),
};

/// Content builder for each nav destination, keyed by id.
final _navBuilders = <int, WidgetBuilder>{
  0: (_) => const DashboardContent(),
  1: (_) => const ChatScreen(embedded: true),
  2: (_) => const VaultListScreen(embedded: true),
  3: (_) => const NotesListScreen(embedded: true),
  4: (_) => const IdeasListScreen(embedded: true),
  5: (_) => const DocumentsListScreen(embedded: true),
  6: (_) => const ChatHistoryScreen(embedded: true),
  7: (_) => const ServerManagementScreen(embedded: true),
  8: (_) => const WikiScreen(embedded: true),
  9: (_) => const SettingsScreen(embedded: true),
};

/// Shell layout with sidebar NavigationRail and content area.
class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  /// One Navigator key per section so sub-navigation is preserved.
  final _navKeys = List.generate(10, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    // Index wiki pages and audit logs for RAG on first unlock
    Future.microtask(() {
      final indexer = ref.read(embeddingIndexProvider.notifier);
      indexer.indexWikiPages();
      indexer.indexAllAuditLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(shellNavigationProvider);
    final theme = Theme.of(context);
    final secretsLocked = ref.watch(secretsLockProvider);
    final visibleDests = ref.watch(visibleNavDestinationsProvider);

    // Map from rail index to destination id and vice versa
    final railToId = <int, int>{};
    int? selectedRailIndex;
    for (var i = 0; i < visibleDests.length; i++) {
      railToId[i] = visibleDests[i].id;
      if (visibleDests[i].id == selectedId) {
        selectedRailIndex = i;
      }
    }

    // If selected item was hidden, fall back to Dashboard
    if (selectedRailIndex == null) {
      Future.microtask(() {
        ref.read(shellNavigationProvider.notifier).state = 0;
      });
      selectedRailIndex = 0;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final navState = _navKeys[selectedId].currentState;
        if (navState != null && navState.canPop()) {
          navState.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('AI VaultIO'),
              const SizedBox(width: 8),
              Text(
                'v${ref.watch(appVersionProvider)}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                secretsLocked ? Icons.lock : Icons.lock_open,
                color: secretsLocked ? Colors.red : null,
                size: 20,
              ),
              tooltip: secretsLocked ? 'Unlock secrets' : 'Lock secrets',
              onPressed: () =>
                  ref.read(secretsLockProvider.notifier).toggle(),
            ),
            IconButton(
              icon: const Icon(Icons.lock),
              tooltip: 'Lock vault',
              onPressed: () => ref.read(authStateProvider.notifier).lock(),
            ),
          ],
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedRailIndex,
              onDestinationSelected: (railIndex) {
                ref.read(shellNavigationProvider.notifier).state =
                    railToId[railIndex]!;
              },
              labelType: NavigationRailLabelType.all,
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Customize sidebar',
                      onPressed: () => _showNavCustomizer(context),
                    ),
                  ),
                ),
              ),
              destinations: [
                for (final dest in visibleDests)
                  NavigationRailDestination(
                    icon: Icon(_navIcons[dest.id]!.$1),
                    selectedIcon: Icon(_navIcons[dest.id]!.$2),
                    label: Text(dest.label),
                  ),
              ],
            ),
            VerticalDivider(
              thickness: 1,
              width: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Expanded(
              child: IndexedStack(
                index: selectedId,
                children: [
                  for (var id = 0; id < 10; id++)
                    _NestedNavigator(
                      navigatorKey: _navKeys[id],
                      builder: _navBuilders[id]!,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNavCustomizer(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _NavCustomizerDialog(),
    );
  }
}

/// Dialog that lets users toggle sidebar items on/off.
class _NavCustomizerDialog extends ConsumerWidget {
  const _NavCustomizerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(navVisibilityProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Customize Sidebar'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Toggle which items appear in the sidebar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final dest in allNavDestinations)
              SwitchListTile(
                dense: true,
                secondary: Icon(
                  _navIcons[dest.id]!.$2,
                  size: 20,
                  color: dest.isSystem
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
                title: Text(dest.label),
                subtitle: dest.isSystem
                    ? Text(
                        'Always visible',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : null,
                value: !hidden.contains(dest.id),
                onChanged: dest.isSystem
                    ? null
                    : (_) =>
                        ref.read(navVisibilityProvider.notifier).toggle(dest.id),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Wraps a screen in its own Navigator so sub-navigation stays
/// within the content area (sidebar persists).
class _NestedNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final WidgetBuilder builder;

  const _NestedNavigator({
    required this.navigatorKey,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (_) => MaterialPageRoute(builder: builder),
    );
  }
}
