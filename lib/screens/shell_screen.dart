import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/embedding_provider.dart';
import '../providers/nav_visibility_provider.dart';
import '../providers/secrets_lock_provider.dart';
import '../providers/shell_navigation_provider.dart';
import '../providers/version_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'chat_history_screen.dart';
import 'chat_screen.dart';
import 'dashboard_content.dart';
import 'documents_list_screen.dart';
import 'ideas_list_screen.dart';
import 'notes_list_screen.dart';
import 'server_management_screen.dart';
import 'settings_screen.dart';
import 'vault_list_screen.dart';
import 'doc_builder_screen.dart';
import 'lance_db_screen.dart';
import 'linear_tasks_screen.dart';
import 'wiki_screen.dart';

// ── Icon pairs (outlined, filled) keyed by destination id ─────────────────

const _navIcons = <int, (IconData, IconData)>{
  0:  (Icons.grid_view_outlined,      Icons.grid_view),
  1:  (Icons.auto_awesome_outlined,   Icons.auto_awesome),
  2:  (Icons.shield_outlined,         Icons.shield),
  3:  (Icons.article_outlined,        Icons.article),
  4:  (Icons.lightbulb_outline,       Icons.lightbulb),
  5:  (Icons.folder_outlined,         Icons.folder),
  6:  (Icons.forum_outlined,          Icons.forum),
  7:  (Icons.dns_outlined,            Icons.dns),
  8:  (Icons.menu_book_outlined,      Icons.menu_book),
  9:  (Icons.settings_outlined,       Icons.settings),
  10: (Icons.auto_fix_high_outlined,  Icons.auto_fix_high),
  11: (Icons.view_kanban_outlined,    Icons.view_kanban),
  12: (Icons.hub_outlined,            Icons.hub),
};

// ── Content builders keyed by destination id ──────────────────────────────

final _navBuilders = <int, WidgetBuilder>{
  0:  (_) => const DashboardContent(),
  1:  (_) => const ChatScreen(embedded: true),
  2:  (_) => const VaultListScreen(embedded: true),
  3:  (_) => const NotesListScreen(embedded: true),
  4:  (_) => const IdeasListScreen(embedded: true),
  5:  (_) => const DocumentsListScreen(embedded: true),
  6:  (_) => const ChatHistoryScreen(embedded: true),
  7:  (_) => const ServerManagementScreen(embedded: true),
  8:  (_) => const WikiScreen(embedded: true),
  9:  (_) => const SettingsScreen(embedded: true),
  10: (_) => const DocBuilderScreen(embedded: true),
  11: (_) => const LinearTasksScreen(embedded: true),
  12: (_) => const LanceDbScreen(),
};

// ── Sidebar navigation groups ─────────────────────────────────────────────
// Settings (id 9) is rendered separately, pinned at the bottom of the sidebar.

const _settingsId = 9;

/// A group of nav destinations rendered together in the sidebar.
/// [header] = null means no section label above the items.
typedef _NavSection = ({String? header, List<int> ids});

const _navSections = <_NavSection>[
  (header: null,            ids: [0, 1]),       // Workspace
  (header: 'VAULT',         ids: [2, 3, 4, 5]), // Vault
  (header: 'AI TOOLS',      ids: [6, 10, 12]),   // AI Tools
  (header: 'INTEGRATIONS',  ids: [11, 7, 8]),   // Integrations
];

// ── Shell ─────────────────────────────────────────────────────────────────

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  /// One Navigator key per section — preserves sub-navigation state.
  final _navKeys = List.generate(13, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final indexer = ref.read(embeddingIndexProvider.notifier);
      indexer.indexWikiPages();
      indexer.indexAllAuditLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedId   = ref.watch(shellNavigationProvider);
    final visibleDests = ref.watch(visibleNavDestinationsProvider);

    // Build rail-index ↔ destination-id maps.
    final railToId = <int, int>{};
    int? selectedRailIndex;
    for (var i = 0; i < visibleDests.length; i++) {
      railToId[i] = visibleDests[i].id;
      if (visibleDests[i].id == selectedId) selectedRailIndex = i;
    }

    // If the selected item was hidden, fall back to Dashboard.
    if (selectedRailIndex == null) {
      Future.microtask(
          () => ref.read(shellNavigationProvider.notifier).state = 0);
      selectedRailIndex = 0;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final navState = _navKeys[selectedId].currentState;
        if (navState != null && navState.canPop()) navState.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.darkScaffold,
        body: Row(
          children: [
            // ── Sidebar ────────────────────────────────────────────
            _Sidebar(
              selectedId: selectedId,
              visibleDestIds: visibleDests.map((d) => d.id).toSet(),
              onSelect: (id) =>
                  ref.read(shellNavigationProvider.notifier).state = id,
              onCustomize: () => _showNavCustomizer(context),
            ),

            // ── Content ────────────────────────────────────────────
            Expanded(
              child: _FadingIndexedStack(
                index: selectedId,
                children: [
                  for (var id = 0; id < 13; id++)
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
      builder: (_) => const _NavCustomizerDialog(),
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────────

class _Sidebar extends ConsumerWidget {
  final int selectedId;
  final Set<int> visibleDestIds;
  final ValueChanged<int> onSelect;
  final VoidCallback onCustomize;

  const _Sidebar({
    required this.selectedId,
    required this.visibleDestIds,
    required this.onSelect,
    required this.onCustomize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secretsLocked = ref.watch(secretsLockProvider);
    final version       = ref.watch(appVersionProvider);

    return Container(
      width: AppSpacing.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(
          right: BorderSide(color: AppColors.sidebarDivider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ───────────────────────────────────────────────
          _SidebarHeader(version: version),
          const _SidebarDivider(),

          // ── Nav items ────────────────────────────────────────────
          Expanded(
            child: Scrollbar(
              thumbVisibility: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.px8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final section in _navSections) ...[
                      // Filter to only visible destinations in this section.
                      if (section.ids
                          .any((id) => visibleDestIds.contains(id))) ...[
                        if (section.header != null) ...[
                          const SizedBox(height: AppSpacing.px8),
                          _SidebarSectionLabel(section.header!),
                        ],
                        for (final id in section.ids)
                          if (visibleDestIds.contains(id))
                            _SidebarNavItem(
                              id: id,
                              selectedId: selectedId,
                              label: allNavDestinations
                                  .firstWhere((d) => d.id == id)
                                  .label,
                              icons: _navIcons[id]!,
                              onTap: () => onSelect(id),
                            ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ── Footer ───────────────────────────────────────────────
          const _SidebarDivider(),
          if (visibleDestIds.contains(_settingsId))
            _SidebarNavItem(
              id: _settingsId,
              selectedId: selectedId,
              label: 'Settings',
              icons: _navIcons[_settingsId]!,
              onTap: () => onSelect(_settingsId),
            ),
          _SidebarFooter(
            secretsLocked: secretsLocked,
            onToggleLock: () =>
                ref.read(secretsLockProvider.notifier).toggle(),
            onLockVault: () => ref.read(authStateProvider.notifier).lock(),
            onCustomize: onCustomize,
          ),
        ],
      ),
    );
  }
}

// ── Sidebar: Header ───────────────────────────────────────────────────────

class _SidebarHeader extends StatelessWidget {
  final String version;
  const _SidebarHeader({required this.version});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.px12, AppSpacing.px14, AppSpacing.px12, AppSpacing.px12),
      child: Row(
        children: [
          // Logo mark
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brand500, AppColors.brand700],
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(Icons.shield, color: Colors.white, size: 16),
          ),
          const SizedBox(width: AppSpacing.px10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'AI VaultIO',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.sidebarTextActive,
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
                Text(
                  'v$version',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.sidebarText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar: Section label ─────────────────────────────────────────────────

class _SidebarSectionLabel extends StatelessWidget {
  final String label;
  const _SidebarSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.px16, AppSpacing.px4, AppSpacing.px16, AppSpacing.px2),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.sidebarSectionLabel,
          letterSpacing: 0.7,
          height: 1,
        ),
      ),
    );
  }
}

// ── Sidebar: Nav item ─────────────────────────────────────────────────────

class _SidebarNavItem extends StatefulWidget {
  final int id;
  final int selectedId;
  final String label;
  final (IconData, IconData) icons;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.id,
    required this.selectedId,
    required this.label,
    required this.icons,
    required this.onTap,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.id == widget.selectedId;

    // Resolve colors based on state.
    final bgColor = isSelected || _hovered
        ? AppColors.sidebarItemActive
        : Colors.transparent;
    final iconColor = isSelected
        ? AppColors.sidebarAccentIcon
        : _hovered
            ? AppColors.sidebarTextHover
            : AppColors.sidebarText;
    final textColor = isSelected
        ? AppColors.sidebarTextActive
        : _hovered
            ? AppColors.sidebarTextHover
            : AppColors.sidebarText;
    final fontWeight =
        isSelected ? FontWeight.w500 : FontWeight.w400;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.px8, vertical: 1),
      child: Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 800),
        preferBelow: false,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit:  (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.px10, vertical: AppSpacing.px8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      isSelected ? widget.icons.$2 : widget.icons.$1,
                      key: ValueKey(isSelected),
                      size: AppSpacing.iconSm,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.px10),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: fontWeight,
                        color: textColor,
                        letterSpacing: -0.1,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sidebar: Footer ───────────────────────────────────────────────────────

class _SidebarFooter extends StatelessWidget {
  final bool secretsLocked;
  final VoidCallback onToggleLock;
  final VoidCallback onLockVault;
  final VoidCallback onCustomize;

  const _SidebarFooter({
    required this.secretsLocked,
    required this.onToggleLock,
    required this.onLockVault,
    required this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.px12, AppSpacing.px6, AppSpacing.px12, AppSpacing.px14),
      child: Row(
        children: [
          _SidebarIconAction(
            icon: secretsLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            tooltip:
                secretsLocked ? 'Unlock secrets' : 'Lock secrets',
            color: secretsLocked ? AppColors.error : null,
            onTap: onToggleLock,
          ),
          const SizedBox(width: AppSpacing.px4),
          _SidebarIconAction(
            icon: Icons.logout_rounded,
            tooltip: 'Lock vault',
            onTap: onLockVault,
          ),
          const Spacer(),
          _SidebarIconAction(
            icon: Icons.tune_rounded,
            tooltip: 'Customize sidebar',
            onTap: onCustomize,
          ),
        ],
      ),
    );
  }
}

// ── Sidebar: Small icon action button ────────────────────────────────────

class _SidebarIconAction extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _SidebarIconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  State<_SidebarIconAction> createState() => _SidebarIconActionState();
}

class _SidebarIconActionState extends State<_SidebarIconAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.color ??
        (_hovered ? AppColors.sidebarTextHover : AppColors.sidebarText);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.all(AppSpacing.px6),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppColors.sidebarItemHover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(widget.icon,
                size: AppSpacing.iconSm, color: iconColor),
          ),
        ),
      ),
    );
  }
}

// ── Sidebar: Thin divider ─────────────────────────────────────────────────

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: AppColors.sidebarDivider,
    );
  }
}

// ── Fading IndexedStack ───────────────────────────────────────────────────
// Provides a subtle fade-in when switching between sections while still
// preserving the state of every section via IndexedStack.

class _FadingIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _FadingIndexedStack({
    required this.index,
    required this.children,
  });

  @override
  State<_FadingIndexedStack> createState() => _FadingIndexedStackState();
}

class _FadingIndexedStackState extends State<_FadingIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 160))
      ..value = 1.0;
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(_FadingIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _ctrl.forward(from: 0.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: IndexedStack(index: widget.index, children: widget.children),
    );
  }
}

// ── Nested navigator ──────────────────────────────────────────────────────
// Each section gets its own Navigator so sub-pages persist while
// navigating between sections.

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

// ── Nav customizer dialog ─────────────────────────────────────────────────

class _NavCustomizerDialog extends ConsumerWidget {
  const _NavCustomizerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(navVisibilityProvider);
    final theme  = Theme.of(context);
    final cs     = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.px24),
      child: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.px20, AppSpacing.px20,
                  AppSpacing.px16, AppSpacing.px16),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: cs.outline)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Customize Sidebar',
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600)),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close_rounded,
                          size: AppSpacing.iconLg,
                          color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),

            // Item list
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.px8),
                child: Column(
                  children: [
                    for (final dest in allNavDestinations)
                      SwitchListTile(
                        dense: true,
                        secondary: Icon(
                          _navIcons[dest.id]!.$2,
                          size: AppSpacing.iconLg,
                          color: dest.isSystem
                              ? cs.onSurfaceVariant
                              : cs.onSurface,
                        ),
                        title: Text(dest.label,
                            style: theme.textTheme.bodyMedium),
                        subtitle: dest.isSystem
                            ? Text('Always visible',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant))
                            : null,
                        value: !hidden.contains(dest.id),
                        onChanged: dest.isSystem
                            ? null
                            : (_) => ref
                                .read(navVisibilityProvider.notifier)
                                .toggle(dest.id),
                      ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.px20, AppSpacing.px12,
                  AppSpacing.px20, AppSpacing.px20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: cs.outline)),
              ),
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
