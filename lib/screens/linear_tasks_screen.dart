import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/linear_models.dart';
import '../providers/linear_provider.dart';
import 'linear_settings_screen.dart';

class LinearTasksScreen extends ConsumerStatefulWidget {
  const LinearTasksScreen({super.key});

  @override
  ConsumerState<LinearTasksScreen> createState() => _LinearTasksScreenState();
}

class _LinearTasksScreenState extends ConsumerState<LinearTasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Filter state
  String _stateTypeFilter = 'all'; // all | triage | backlog | unstarted | started
  int? _priorityFilter; // null = all

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linear = ref.watch(linearProvider);

    if (!linear.isConnected && linear.status == LinearConnectionStatus.disconnected) {
      return _NotConnectedView(theme: theme);
    }

    if (linear.status == LinearConnectionStatus.connecting ||
        (linear.status == LinearConnectionStatus.syncing && linear.issues.isEmpty)) {
      return Scaffold(
        appBar: _buildAppBar(context, theme, linear),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                linear.statusMessage ?? 'Loading...',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(context, theme, linear),
      body: Column(
        children: [
          // ── Filter Bar ─────────────────────────────────────────────────
          _FilterBar(
            linear: linear,
            stateTypeFilter: _stateTypeFilter,
            priorityFilter: _priorityFilter,
            onStateTypeChanged: (v) => setState(() => _stateTypeFilter = v),
            onPriorityChanged: (v) => setState(() => _priorityFilter = v),
            onTeamChanged: (id) =>
                ref.read(linearProvider.notifier).setTeamFilter(id),
            onProjectChanged: (id) =>
                ref.read(linearProvider.notifier).setProjectFilter(id),
            onToggleMine: () =>
                ref.read(linearProvider.notifier).toggleMyIssues(),
          ),

          // ── Tabs ────────────────────────────────────────────────────────
          TabBar(
            controller: _tabController,
            tabs: [
              const Tab(text: 'Issues'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Projects'),
                    const SizedBox(width: 4),
                    _Badge(count: linear.projectsFromIssues.length),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Teams'),
                    const SizedBox(width: 4),
                    _Badge(count: linear.teamsFromIssues.length),
                  ],
                ),
              ),
            ],
          ),

          // ── Tab Content ─────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _IssuesTab(
                  linear: linear,
                  stateTypeFilter: _stateTypeFilter,
                  priorityFilter: _priorityFilter,
                  onCreateIssue: () => _showCreateIssueDialog(context, linear),
                ),
                _ProjectsTab(linear: linear),
                _TeamsTab(linear: linear),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: linear.isConnected
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateIssueDialog(context, linear),
              icon: const Icon(Icons.add),
              label: const Text('New Issue'),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, ThemeData theme, LinearState linear) {
    return AppBar(
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF5E6AD2).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.linear_scale,
                color: Color(0xFF5E6AD2), size: 16),
          ),
          const SizedBox(width: 8),
          const Text('Tasks'),
          if (linear.status == LinearConnectionStatus.syncing) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
      actions: [
        if (linear.isConnected)
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync issues',
            onPressed: () => ref.read(linearProvider.notifier).sync(),
          ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Linear settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const LinearSettingsScreen()),
          ),
        ),
      ],
    );
  }

  void _showCreateIssueDialog(BuildContext context, LinearState linear) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _CreateIssueDialog(linear: linear),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Not Connected View
// ─────────────────────────────────────────────────────────────────────────────

class _NotConnectedView extends StatelessWidget {
  final ThemeData theme;

  const _NotConnectedView({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const LinearSettingsScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF5E6AD2).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.linear_scale,
                    color: Color(0xFF5E6AD2), size: 40),
              ),
              const SizedBox(height: 24),
              Text('Connect to Linear',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'View and manage your Linear issues directly in AI VaultIO. '
                'Connect your workspace to get started.',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const LinearSettingsScreen()),
                ),
                icon: const Icon(Icons.link),
                label: const Text('Connect Linear'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Bar
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final LinearState linear;
  final String stateTypeFilter;
  final int? priorityFilter;
  final ValueChanged<String> onStateTypeChanged;
  final ValueChanged<int?> onPriorityChanged;
  final ValueChanged<String?> onTeamChanged;
  final ValueChanged<String?> onProjectChanged;
  final VoidCallback onToggleMine;

  const _FilterBar({
    required this.linear,
    required this.stateTypeFilter,
    required this.priorityFilter,
    required this.onStateTypeChanged,
    required this.onPriorityChanged,
    required this.onTeamChanged,
    required this.onProjectChanged,
    required this.onToggleMine,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teams = linear.teamsFromIssues;
    final projects = linear.projectsFromIssues;

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // State type chips
            _FilterChip(
              label: 'All',
              selected: stateTypeFilter == 'all',
              onTap: () => onStateTypeChanged('all'),
            ),
            const SizedBox(width: 4),
            _FilterChip(
              label: 'In Progress',
              color: Colors.blue,
              selected: stateTypeFilter == 'started',
              onTap: () => onStateTypeChanged('started'),
            ),
            const SizedBox(width: 4),
            _FilterChip(
              label: 'Todo',
              color: Colors.orange,
              selected: stateTypeFilter == 'unstarted',
              onTap: () => onStateTypeChanged('unstarted'),
            ),
            const SizedBox(width: 4),
            _FilterChip(
              label: 'Backlog',
              color: Colors.grey,
              selected: stateTypeFilter == 'backlog',
              onTap: () => onStateTypeChanged('backlog'),
            ),
            const SizedBox(width: 4),
            _FilterChip(
              label: 'Done',
              color: Colors.green,
              selected: stateTypeFilter == 'completed',
              onTap: () => onStateTypeChanged('completed'),
            ),
            const SizedBox(width: 8),
            const SizedBox(height: 24, child: VerticalDivider(width: 1)),
            const SizedBox(width: 8),

            // My issues toggle
            _FilterChip(
              label: 'My Issues',
              icon: Icons.person,
              selected: linear.showOnlyMine,
              onTap: onToggleMine,
              color: Colors.purple,
            ),
            const SizedBox(width: 8),

            // Team filter
            if (teams.length > 1) ...[
              _DropdownChip<String?>(
                label: linear.selectedTeamId != null
                    ? teams
                        .firstWhere((t) => t.id == linear.selectedTeamId,
                            orElse: () => teams.first)
                        .name
                    : 'All Teams',
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All Teams')),
                  ...teams.map((t) => DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text('${t.key}: ${t.name}'),
                      )),
                ],
                onChanged: onTeamChanged,
              ),
              const SizedBox(width: 8),
            ],

            // Project filter
            if (projects.isNotEmpty) ...[
              _DropdownChip<String?>(
                label: linear.selectedProjectId != null
                    ? projects
                        .firstWhere((p) => p.id == linear.selectedProjectId,
                            orElse: () => projects.first)
                        .name
                    : 'All Projects',
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All Projects')),
                  ...projects.map((p) => DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(p.name),
                      )),
                ],
                onChanged: onProjectChanged,
              ),
              const SizedBox(width: 8),
            ],

            // Priority filter
            _DropdownChip<int?>(
              label: priorityFilter != null
                  ? LinearPriority.fromValue(priorityFilter!).label
                  : 'All Priority',
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('All Priority')),
                ...LinearPriority.values.map((p) => DropdownMenuItem<int?>(
                      value: p.value,
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 10, color: p.color),
                          const SizedBox(width: 6),
                          Text(p.label),
                        ],
                      ),
                    )),
              ],
              onChanged: onPriorityChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icon;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = color ?? theme.colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? activeColor.withValues(alpha: 0.6)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12,
                  color: selected
                      ? activeColor
                      : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? activeColor
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownChip<T> extends StatelessWidget {
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _DropdownChip({
    required this.label,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: null,
          hint: Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          items: items,
          onChanged: onChanged,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Issues Tab
// ─────────────────────────────────────────────────────────────────────────────

class _IssuesTab extends StatelessWidget {
  final LinearState linear;
  final String stateTypeFilter;
  final int? priorityFilter;
  final VoidCallback onCreateIssue;

  const _IssuesTab({
    required this.linear,
    required this.stateTypeFilter,
    required this.priorityFilter,
    required this.onCreateIssue,
  });

  List<LinearIssue> get _filteredIssues {
    var issues = linear.filteredIssues;
    if (stateTypeFilter != 'all') {
      issues = issues.where((i) => i.state.type == stateTypeFilter).toList();
    }
    if (priorityFilter != null) {
      issues =
          issues.where((i) => i.priorityValue == priorityFilter).toList();
    }
    return issues
      ..sort((a, b) {
        // Sort: in-progress first, then by priority, then by due date
        if (a.state.isInProgress != b.state.isInProgress) {
          return a.state.isInProgress ? -1 : 1;
        }
        if (a.priorityValue != b.priorityValue) {
          // Priority 1 (urgent) comes first, 0 (no priority) last
          final pa = a.priorityValue == 0 ? 99 : a.priorityValue;
          final pb = b.priorityValue == 0 ? 99 : b.priorityValue;
          return pa.compareTo(pb);
        }
        return b.updatedAt.compareTo(a.updatedAt);
      });
  }

  @override
  Widget build(BuildContext context) {
    final issues = _filteredIssues;

    if (issues.isEmpty && linear.issues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'No issues yet',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onCreateIssue,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Issue'),
            ),
          ],
        ),
      );
    }

    if (issues.isEmpty) {
      return Center(
        child: Text(
          'No issues match the current filters',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    // Group by state type for a Linear-like view
    final grouped = <String, List<LinearIssue>>{};
    final stateOrder = [
      'triage',
      'unstarted',
      'started',
      'backlog',
      'completed',
      'cancelled'
    ];

    for (final issue in issues) {
      grouped.putIfAbsent(issue.state.type, () => []).add(issue);
    }

    final sections = stateOrder.where((t) => grouped.containsKey(t)).toList();
    // Add any unknown types
    for (final type in grouped.keys) {
      if (!sections.contains(type)) sections.add(type);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final type = sections[index];
        final sectionIssues = grouped[type]!;
        return _IssueSection(
          stateType: type,
          issues: sectionIssues,
          allStates: linear.teams
              .expand((t) => t.states)
              .toList(),
        );
      },
    );
  }
}

class _IssueSection extends ConsumerStatefulWidget {
  final String stateType;
  final List<LinearIssue> issues;
  final List<LinearIssueState> allStates;

  const _IssueSection({
    required this.stateType,
    required this.issues,
    required this.allStates,
  });

  @override
  ConsumerState<_IssueSection> createState() => _IssueSectionState();
}

class _IssueSectionState extends ConsumerState<_IssueSection> {
  bool _expanded = true;

  String get _sectionLabel {
    switch (widget.stateType) {
      case 'triage':
        return 'Triage';
      case 'backlog':
        return 'Backlog';
      case 'unstarted':
        return 'Todo';
      case 'started':
        return 'In Progress';
      case 'completed':
        return 'Done';
      case 'cancelled':
        return 'Cancelled';
      default:
        return widget.stateType;
    }
  }

  Color get _sectionColor {
    switch (widget.stateType) {
      case 'triage':
        return Colors.orange;
      case 'backlog':
        return Colors.grey;
      case 'unstarted':
        return Colors.amber;
      case 'started':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red.shade300;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _sectionColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _sectionLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                _Badge(count: widget.issues.length),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...widget.issues.map(
            (issue) => _IssueCard(issue: issue, allStates: widget.allStates),
          ),
      ],
    );
  }
}

class _IssueCard extends ConsumerWidget {
  final LinearIssue issue;
  final List<LinearIssueState> allStates;

  const _IssueCard({required this.issue, required this.allStates});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Priority indicator
              _PriorityDot(priority: issue.priority),
              const SizedBox(width: 10),

              // State dot
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _StateDot(state: issue.state),
              ),
              const SizedBox(width: 10),

              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Identifier + title
                    Row(
                      children: [
                        Text(
                          issue.identifier,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            issue.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              decoration: issue.state.isCompleted ||
                                      issue.state.isCancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: issue.state.isCompleted ||
                                      issue.state.isCancelled
                                  ? theme.colorScheme.onSurfaceVariant
                                  : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Meta row: project, assignee, due date
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        // Team key
                        _MetaChip(
                          icon: Icons.group,
                          label: issue.team.key,
                          color: Colors.blueGrey,
                        ),
                        // Project
                        if (issue.project != null)
                          _MetaChip(
                            icon: Icons.folder_outlined,
                            label: issue.project!.name,
                            color: issue.project!.flutterColor ??
                                Colors.grey,
                          ),
                        // Assignee
                        if (issue.assignee != null)
                          _MetaChip(
                            icon: Icons.person_outline,
                            label: issue.assignee!.name,
                            color: Colors.purple,
                          ),
                        // Due date
                        if (issue.dueDate != null)
                          _MetaChip(
                            icon: Icons.calendar_today,
                            label: _formatDate(issue.dueDate!),
                            color: issue.isOverdue
                                ? Colors.red
                                : issue.isDueSoon
                                    ? Colors.orange
                                    : Colors.grey,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}';
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scrollController) => _IssueDetailSheet(
          issue: issue,
          allStates: allStates,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  final LinearPriority priority;

  const _PriorityDot({required this.priority});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (priority) {
      case LinearPriority.urgent:
        icon = Icons.error;
      case LinearPriority.high:
        icon = Icons.keyboard_double_arrow_up;
      case LinearPriority.medium:
        icon = Icons.keyboard_arrow_up;
      case LinearPriority.low:
        icon = Icons.keyboard_arrow_down;
      case LinearPriority.noPriority:
        icon = Icons.remove;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Icon(icon, size: 14, color: priority.color),
    );
  }
}

class _StateDot extends StatelessWidget {
  final LinearIssueState state;

  const _StateDot({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = state.flutterColor;
    if (state.isCompleted) {
      return Icon(Icons.check_circle, size: 14, color: color);
    } else if (state.isCancelled) {
      return Icon(Icons.cancel, size: 14, color: color);
    } else if (state.isInProgress) {
      return Icon(Icons.pending, size: 14, color: color);
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Issue Detail Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _IssueDetailSheet extends ConsumerWidget {
  final LinearIssue issue;
  final List<LinearIssueState> allStates;
  final ScrollController scrollController;

  const _IssueDetailSheet({
    required this.issue,
    required this.allStates,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final teamStates = allStates
        .where((s) => issue.team.states.any((ts) => ts.id == s.id))
        .toList();
    // Fall back to issue's own team states if available
    final statesForTeam =
        issue.team.states.isNotEmpty ? issue.team.states : teamStates;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _PriorityDot(priority: issue.priority),
                const SizedBox(width: 6),
                _StateDot(state: issue.state),
                const SizedBox(width: 8),
                Text(
                  issue.identifier,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  tooltip: 'Open in Linear',
                  onPressed: () => launchUrl(
                    Uri.parse(issue.url),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Scrollable content
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  issue.title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Metadata grid
                _DetailRow(
                  label: 'Status',
                  child: statesForTeam.isNotEmpty
                      ? DropdownButton<String>(
                          value: issue.state.id,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          items: statesForTeam
                              .map((s) => DropdownMenuItem<String>(
                                    value: s.id,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: s.flutterColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(s.name),
                                      ],
                                    ),
                                  ))
                              .toList(),
                          onChanged: (newStateId) {
                            if (newStateId != null) {
                              ref
                                  .read(linearProvider.notifier)
                                  .updateIssueState(
                                    issueId: issue.id,
                                    stateId: newStateId,
                                  );
                              Navigator.pop(context);
                            }
                          },
                        )
                      : _StateChip(state: issue.state),
                ),
                _DetailRow(
                  label: 'Priority',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PriorityDot(priority: issue.priority),
                      const SizedBox(width: 4),
                      Text(issue.priority.label),
                    ],
                  ),
                ),
                _DetailRow(
                  label: 'Team',
                  child: Text('${issue.team.key}: ${issue.team.name}'),
                ),
                if (issue.project != null)
                  _DetailRow(
                    label: 'Project',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (issue.project!.flutterColor != null)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: issue.project!.flutterColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 4),
                        Text(issue.project!.name),
                      ],
                    ),
                  ),
                if (issue.assignee != null)
                  _DetailRow(
                    label: 'Assignee',
                    child: Text(issue.assignee!.name),
                  ),
                if (issue.dueDate != null)
                  _DetailRow(
                    label: 'Due Date',
                    child: Text(
                      '${issue.dueDate!.year}-'
                      '${issue.dueDate!.month.toString().padLeft(2, '0')}-'
                      '${issue.dueDate!.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: issue.isOverdue ? Colors.red : null,
                        fontWeight: issue.isOverdue ? FontWeight.bold : null,
                      ),
                    ),
                  ),
                _DetailRow(
                  label: 'Created',
                  child: Text(_formatDate(issue.createdAt)),
                ),
                _DetailRow(
                  label: 'Updated',
                  child: Text(_formatDate(issue.updatedAt)),
                ),

                // Description
                if (issue.description != null &&
                    issue.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Description',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    issue.description!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _DetailRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final LinearIssueState state;

  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = state.flutterColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        state.name,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Projects Tab
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectsTab extends StatelessWidget {
  final LinearState linear;

  const _ProjectsTab({required this.linear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projects = linear.projectsFromIssues;

    if (projects.isEmpty) {
      return Center(
        child: Text(
          'No projects found',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        final projectIssues =
            linear.issues.where((i) => i.project?.id == project.id).toList();
        final activeCount = projectIssues
            .where((i) =>
                !i.state.isCompleted && !i.state.isCancelled)
            .length;
        final completedCount =
            projectIssues.where((i) => i.state.isCompleted).length;
        final progress = projectIssues.isEmpty
            ? 0.0
            : completedCount / projectIssues.length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: project.flutterColor ??
                            theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        project.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    _ProjectStateBadge(state: project.state),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '$activeCount active',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$completedCount completed',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.green),
                    ),
                    const Spacer(),
                    Text(
                      '${(progress * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    color: project.flutterColor ?? Colors.green,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProjectStateBadge extends StatelessWidget {
  final String state;

  const _ProjectStateBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (state) {
      case 'started':
        color = Colors.blue;
      case 'completed':
        color = Colors.green;
      case 'paused':
        color = Colors.orange;
      case 'cancelled':
        color = Colors.red;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        state[0].toUpperCase() + state.substring(1),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Teams Tab
// ─────────────────────────────────────────────────────────────────────────────

class _TeamsTab extends StatelessWidget {
  final LinearState linear;

  const _TeamsTab({required this.linear});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teams = linear.teamsFromIssues;

    if (teams.isEmpty) {
      return Center(
        child: Text(
          'No teams found',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: teams.length,
      itemBuilder: (context, index) {
        final team = teams[index];
        final teamIssues =
            linear.issues.where((i) => i.team.id == team.id).toList();
        final active = teamIssues
            .where(
                (i) => !i.state.isCompleted && !i.state.isCancelled)
            .length;
        final urgent = teamIssues
            .where((i) => i.priorityValue == 1)
            .length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        team.key,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        team.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _TeamStat(
                        label: 'Active',
                        value: active,
                        color: Colors.blue),
                    const SizedBox(width: 16),
                    _TeamStat(
                        label: 'Urgent',
                        value: urgent,
                        color: urgent > 0 ? Colors.red : Colors.grey),
                    const SizedBox(width: 16),
                    _TeamStat(
                        label: 'Total',
                        value: teamIssues.length,
                        color: Colors.grey),
                  ],
                ),
                if (team.states.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: team.states
                        .take(6)
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: s.flutterColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                s.name,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(
                                        color: s.flutterColor,
                                        fontSize: 10),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TeamStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _TeamStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '$value',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Issue Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CreateIssueDialog extends ConsumerStatefulWidget {
  final LinearState linear;

  const _CreateIssueDialog({required this.linear});

  @override
  ConsumerState<_CreateIssueDialog> createState() =>
      _CreateIssueDialogState();
}

class _CreateIssueDialogState extends ConsumerState<_CreateIssueDialog> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedTeamId;
  String? _selectedStateId;
  String? _selectedProjectId;
  int _priority = 0;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    final teams = widget.linear.teamsFromIssues;
    if (teams.isNotEmpty) _selectedTeamId = teams.first.id;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  List<LinearIssueState> get _statesForTeam {
    if (_selectedTeamId == null) return [];
    final teams = widget.linear.teams.isNotEmpty
        ? widget.linear.teams
        : widget.linear.teamsFromIssues;
    try {
      return teams.firstWhere((t) => t.id == _selectedTeamId).states;
    } catch (_) {
      return [];
    }
  }

  Future<void> _create() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _selectedTeamId == null) return;

    setState(() => _creating = true);

    final issue = await ref.read(linearProvider.notifier).createIssue(
          teamId: _selectedTeamId!,
          title: title,
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          stateId: _selectedStateId,
          priority: _priority,
          projectId: _selectedProjectId,
        );

    if (mounted) {
      Navigator.pop(context);
      if (issue != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created ${issue.identifier}: ${issue.title}'),
            action: SnackBarAction(
              label: 'Open in Linear',
              onPressed: () => launchUrl(
                Uri.parse(issue.url),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final teams = widget.linear.teamsFromIssues;
    final projects = widget.linear.projectsFromIssues;
    final states = _statesForTeam;

    return AlertDialog(
      title: const Text('New Issue'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Team selector
              DropdownButtonFormField<String>(
                value: _selectedTeamId,
                decoration: const InputDecoration(
                  labelText: 'Team *',
                  border: OutlineInputBorder(),
                ),
                items: teams
                    .map((t) => DropdownMenuItem<String>(
                          value: t.id,
                          child: Text('${t.key}: ${t.name}'),
                        ))
                    .toList(),
                onChanged: (id) {
                  setState(() {
                    _selectedTeamId = id;
                    _selectedStateId = null;
                  });
                },
              ),
              const SizedBox(height: 12),

              // State selector
              if (states.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  value: _selectedStateId,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                        value: null, child: Text('Default')),
                    ...states.map((s) => DropdownMenuItem<String>(
                          value: s.id,
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: s.flutterColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(s.name),
                            ],
                          ),
                        )),
                  ],
                  onChanged: (id) => setState(() => _selectedStateId = id),
                ),
                const SizedBox(height: 12),
              ],

              // Priority
              DropdownButtonFormField<int>(
                value: _priority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(),
                ),
                items: LinearPriority.values
                    .map((p) => DropdownMenuItem<int>(
                          value: p.value,
                          child: Row(
                            children: [
                              Icon(Icons.circle,
                                  size: 10, color: p.color),
                              const SizedBox(width: 8),
                              Text(p.label),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _priority = v ?? 0),
              ),
              const SizedBox(height: 12),

              // Project
              if (projects.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _selectedProjectId,
                  decoration: const InputDecoration(
                    labelText: 'Project',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                        value: null, child: Text('No project')),
                    ...projects.map((p) => DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(p.name),
                        )),
                  ],
                  onChanged: (id) =>
                      setState(() => _selectedProjectId = id),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _creating ? null : _create,
          child: _creating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
