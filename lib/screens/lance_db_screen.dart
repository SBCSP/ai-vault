import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/embedding_provider.dart';
import '../providers/vector_db_provider.dart';
import '../services/lance_db_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

String _fmtDate(int ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  final h = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '${d.year}-$m-$day  $h:$min';
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _typeCountsProvider =
    FutureProvider.autoDispose<List<TypeCount>>((ref) async {
  return LanceDbService.getTypeCounts();
});

final _browserFilterProvider = StateProvider.autoDispose<String>((ref) => '');
final _browserPageProvider   = StateProvider.autoDispose<int>((ref) => 0);

const _pageSize = 50;

final _browserRowsProvider = FutureProvider.autoDispose
    .family<List<EmbeddingRow>, ({String filter, int page})>((ref, args) async {
  return LanceDbService.getRowsPage(
    sourceTypeFilter: args.filter,
    offset: args.page * _pageSize,
    limit: _pageSize,
  );
});

// ── Screen ────────────────────────────────────────────────────────────────────

/// Full LanceDB management tool: Overview / Collections / Browser tabs.
class LanceDbScreen extends ConsumerStatefulWidget {
  const LanceDbScreen({super.key});

  @override
  ConsumerState<LanceDbScreen> createState() => _LanceDbScreenState();
}

class _LanceDbScreenState extends ConsumerState<LanceDbScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) return;
    switch (_tabs.index) {
      case 1: // Collections — always fetch fresh
        ref.invalidate(_typeCountsProvider);
      case 2: // Browser — always fetch fresh
        ref.invalidate(_browserRowsProvider);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vectorDb = ref.watch(vectorDbProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LanceDB'),
        actions: [
          if (vectorDb.isInitialized) ...[
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh stats',
              onPressed: () {
                ref.read(vectorDbProvider.notifier).refreshStats();
                ref.invalidate(_typeCountsProvider);
              },
            ),
            const SizedBox(width: AppSpacing.px8),
          ],
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Collections'),
            Tab(text: 'Browser'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(vectorDb: vectorDb),
          _CollectionsTab(vectorDb: vectorDb),
          _BrowserTab(vectorDb: vectorDb),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — OVERVIEW
// ══════════════════════════════════════════════════════════════════════════════

class _OverviewTab extends ConsumerWidget {
  final VectorDbState vectorDb;
  const _OverviewTab({required this.vectorDb});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme  = Theme.of(context);
    final cs     = theme.colorScheme;
    final embDim = ref.watch(embeddingDimProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.contentPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusBanner(vectorDb: vectorDb),
              const SizedBox(height: AppSpacing.px24),

              if (vectorDb.isInitialized && vectorDb.stats != null) ...[
                _MetricRow(
                  stats: vectorDb.stats!,
                  isLoadingStats: vectorDb.isLoadingStats,
                ),
                const SizedBox(height: AppSpacing.px24),
              ],

              _SectionLabel('Configuration'),
              const SizedBox(height: AppSpacing.px8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.px20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Embedding Dimension',
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpacing.px4),
                      Text(
                        'Must match the model used to generate embeddings. '
                        'Changing this requires a full re-index.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.px16),
                      _DimSelector(current: embDim, ref: ref),
                    ],
                  ),
                ),
              ),

              if (vectorDb.isInitialized && vectorDb.stats?.dbPath != null) ...[
                const SizedBox(height: AppSpacing.px24),
                _SectionLabel('Storage'),
                const SizedBox(height: AppSpacing.px8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.px20),
                    child: Row(
                      children: [
                        Icon(Icons.folder_outlined,
                            size: AppSpacing.iconLg,
                            color: cs.onSurfaceVariant),
                        const SizedBox(width: AppSpacing.px12),
                        Expanded(
                          child: SelectableText(
                            vectorDb.stats!.dbPath,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded,
                              size: AppSpacing.iconMd),
                          tooltip: 'Copy path',
                          onPressed: () => Clipboard.setData(
                              ClipboardData(text: vectorDb.stats!.dbPath)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (vectorDb.isInitialized) ...[
                const SizedBox(height: AppSpacing.px24),
                _SectionLabel('Index Management'),
                const SizedBox(height: AppSpacing.px8),
                _IndexManagementCard(vectorDb: vectorDb),
              ],

              if (!vectorDb.isInitialized && !vectorDb.isInitializing) ...[
                const SizedBox(height: AppSpacing.px24),
                _SetupRequiredCard(
                  error: vectorDb.error,
                  onRetry: () =>
                      ref.read(vectorDbProvider.notifier).reinitialize(),
                ),
              ],

              const SizedBox(height: AppSpacing.px48),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — COLLECTIONS
// ══════════════════════════════════════════════════════════════════════════════

class _CollectionsTab extends ConsumerWidget {
  final VectorDbState vectorDb;
  const _CollectionsTab({required this.vectorDb});

  // Human-readable labels + icons for each source type
  static const _meta = <String, ({String label, IconData icon, Color color})>{
    'vault_entry':    (label: 'Secrets',       icon: Icons.lock_outline_rounded,    color: AppColors.brand500),
    'note':           (label: 'Notes',          icon: Icons.sticky_note_2_outlined,  color: Color(0xFF10B981)),
    'idea':           (label: 'Ideas',          icon: Icons.lightbulb_outline_rounded, color: Color(0xFFF59E0B)),
    'document_chunk': (label: 'Documents',      icon: Icons.description_outlined,    color: Color(0xFF8B5CF6)),
    'chat_session':   (label: 'Chat Sessions',  icon: Icons.forum_outlined,          color: Color(0xFF06B6D4)),
    'wiki_page':      (label: 'Wiki Pages',     icon: Icons.menu_book_outlined,      color: Color(0xFF64748B)),
    'audit_log':      (label: 'Audit Logs',     icon: Icons.history_rounded,         color: Color(0xFFEF4444)),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(_typeCountsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.contentPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!vectorDb.isInitialized)
                _UnavailableBanner()
              else
                counts.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, _) => _ErrorCard(error: e.toString()),
                  data: (data) => _CollectionsGrid(
                    counts: data,
                    vectorDb: vectorDb,
                  ),
                ),
              const SizedBox(height: AppSpacing.px48),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionsGrid extends ConsumerWidget {
  final List<TypeCount> counts;
  final VectorDbState vectorDb;
  const _CollectionsGrid({required this.counts, required this.vectorDb});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCount = counts.fold<int>(0, (s, c) => s + c.count.toInt());

    if (counts.isEmpty) {
      return _EmptyState(
        icon: Icons.layers_outlined,
        title: 'No embeddings yet',
        subtitle: 'Index your content from the Overview tab to populate collections.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary row
        Row(
          children: [
            Expanded(
              child: _SummaryChip(
                label: 'Total Vectors',
                value: totalCount.toString(),
                icon: Icons.data_array_rounded,
                color: AppColors.brand500,
              ),
            ),
            const SizedBox(width: AppSpacing.px12),
            Expanded(
              child: _SummaryChip(
                label: 'Collections',
                value: counts.length.toString(),
                icon: Icons.layers_rounded,
                color: AppColors.slate500,
              ),
            ),
            const SizedBox(width: AppSpacing.px12),
            Expanded(
              child: _SummaryChip(
                label: 'Index',
                value: vectorDb.stats?.hasIndex == true ? 'HNSW' : 'None',
                icon: Icons.account_tree_rounded,
                color: vectorDb.stats?.hasIndex == true
                    ? AppColors.success
                    : AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.px20),

        // Collection cards grid
        ...counts.map((tc) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.px12),
          child: _CollectionCard(typeCount: tc, ref: ref),
        )),
      ],
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final TypeCount typeCount;
  final WidgetRef ref;
  const _CollectionCard({required this.typeCount, required this.ref});

  static const _meta = _CollectionsTab._meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    final m     = _meta[typeCount.sourceType];
    final label = m?.label ?? typeCount.sourceType;
    final icon  = m?.icon  ?? Icons.storage_rounded;
    final color = m?.color ?? AppColors.brand500;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.px16),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(icon, color: color, size: AppSpacing.iconLg),
            ),
            const SizedBox(width: AppSpacing.px16),

            // Label + source_type
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600)),
                  Text(typeCount.sourceType,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace')),
                ],
              ),
            ),

            // Count badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.px12, vertical: AppSpacing.px6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Text(
                '${typeCount.count}',
                style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: AppSpacing.px8),

            // Browse button
            OutlinedButton.icon(
              icon: const Icon(Icons.table_rows_outlined, size: 14),
              label: const Text('Browse'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSpacing.buttonHeightSm)),
              onPressed: () => _browseCollection(context, typeCount.sourceType),
            ),
            const SizedBox(width: AppSpacing.px8),

            // Delete button
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  color: cs.error, size: AppSpacing.iconLg),
              tooltip: 'Delete collection',
              onPressed: () =>
                  _confirmDeleteCollection(context, typeCount, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _browseCollection(BuildContext context, String sourceType) {
    // Switch to Browser tab and pre-filter
    ref.read(_browserFilterProvider.notifier).state = sourceType;
    ref.read(_browserPageProvider.notifier).state = 0;
    // Find ancestor tab controller
    final tabState = context
        .findAncestorStateOfType<_LanceDbScreenState>();
    tabState?._tabs.animateTo(2);
  }

  Future<void> _confirmDeleteCollection(
      BuildContext context, TypeCount tc, WidgetRef ref) async {
    final m     = _meta[tc.sourceType];
    final label = m?.label ?? tc.sourceType;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "$label" Collection?'),
        content: Text(
          'Permanently removes all ${tc.count} "${tc.sourceType}" embeddings. '
          'RAG search for this content type will stop working until re-indexed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      try {
        await LanceDbService.deleteByType(tc.sourceType);
        ref.invalidate(_typeCountsProvider);
        ref.read(vectorDbProvider.notifier).refreshStats();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Deleted $label collection (${tc.count} vectors)'),
          ));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
          ));
        }
      }
    }
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.px16, vertical: AppSpacing.px12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.iconMd, color: color),
          const SizedBox(width: AppSpacing.px10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant)),
              Text(value,
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 — BROWSER
// ══════════════════════════════════════════════════════════════════════════════

class _BrowserTab extends ConsumerStatefulWidget {
  final VectorDbState vectorDb;
  const _BrowserTab({required this.vectorDb});

  @override
  ConsumerState<_BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends ConsumerState<_BrowserTab> {
  static const _sourceTypes = [
    '',
    'vault_entry',
    'note',
    'idea',
    'document_chunk',
    'chat_session',
    'wiki_page',
    'audit_log',
  ];

  static const _typeLabels = {
    '':               'All types',
    'vault_entry':    'Secrets',
    'note':           'Notes',
    'idea':           'Ideas',
    'document_chunk': 'Documents',
    'chat_session':   'Chat Sessions',
    'wiki_page':      'Wiki Pages',
    'audit_log':      'Audit Logs',
  };

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final cs          = theme.colorScheme;
    final filter      = ref.watch(_browserFilterProvider);
    final page        = ref.watch(_browserPageProvider);
    final rowsAsync   = ref.watch(
      _browserRowsProvider((filter: filter, page: page)),
    );

    if (!widget.vectorDb.isInitialized) {
      return Center(child: _UnavailableBanner());
    }

    return Column(
      children: [
        // ── Toolbar ────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.contentPadding,
              vertical: AppSpacing.px12),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              bottom: BorderSide(color: cs.outline),
            ),
          ),
          child: Row(
            children: [
              // Type filter dropdown
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: filter,
                  isDense: true,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  items: _sourceTypes.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(_typeLabels[t] ?? t,
                        style: theme.textTheme.bodySmall),
                  )).toList(),
                  onChanged: (v) {
                    ref.read(_browserFilterProvider.notifier).state = v ?? '';
                    ref.read(_browserPageProvider.notifier).state = 0;
                  },
                ),
              ),

              const Spacer(),

              // Page info
              rowsAsync.when(
                data: (rows) {
                  final start = page * _pageSize + 1;
                  final end   = page * _pageSize + rows.length;
                  return Text(
                    rows.isEmpty
                        ? 'No rows'
                        : '$start–$end  (page ${page + 1})',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              const SizedBox(width: AppSpacing.px16),

              // Pagination controls
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous page',
                onPressed: page == 0
                    ? null
                    : () => ref
                        .read(_browserPageProvider.notifier)
                        .state = page - 1,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Next page',
                onPressed: rowsAsync.whenOrNull(
                  data: (rows) => rows.length == _pageSize
                      ? () => ref
                          .read(_browserPageProvider.notifier)
                          .state = page + 1
                      : null,
                ),
              ),
            ],
          ),
        ),

        // ── Table ───────────────────────────────────────────────────────────
        Expanded(
          child: rowsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: _ErrorCard(error: e.toString())),
            data: (rows) {
              if (rows.isEmpty) {
                return _EmptyState(
                  icon: Icons.table_rows_outlined,
                  title: 'No rows',
                  subtitle: filter.isEmpty
                      ? 'The embeddings table is empty. Index some content first.'
                      : 'No rows for source_type "$filter".',
                );
              }
              return _EmbeddingTable(rows: rows, filter: filter, page: page);
            },
          ),
        ),
      ],
    );
  }
}

class _EmbeddingTable extends ConsumerWidget {
  final List<EmbeddingRow> rows;
  final String filter;
  final int page;
  const _EmbeddingTable({
    required this.rows,
    required this.filter,
    required this.page,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 44,
          columnSpacing: AppSpacing.px16,
          horizontalMargin: AppSpacing.contentPadding,
          headingTextStyle: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          dividerThickness: 1,
          columns: const [
            DataColumn(label: Text('SOURCE ID')),
            DataColumn(label: Text('TYPE')),
            DataColumn(label: Text('MODEL')),
            DataColumn(label: Text('HASH')),
            DataColumn(label: Text('CREATED')),
            DataColumn(label: Text('')),
          ],
          rows: rows.map((row) {
            return DataRow(
              cells: [
                // source_id — truncated with copy on tap
                DataCell(
                  _CopyableCell(
                    display: _trunc(row.sourceId, 28),
                    full: row.sourceId,
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace'),
                  ),
                ),
                // source_type — colored badge
                DataCell(_TypeBadge(row.sourceType)),
                // model_name
                DataCell(Text(
                  _trunc(row.modelName, 22),
                  style: theme.textTheme.bodySmall,
                )),
                // content_hash — first 8 chars
                DataCell(
                  _CopyableCell(
                    display: row.contentHash.length > 8
                        ? row.contentHash.substring(0, 8)
                        : row.contentHash,
                    full: row.contentHash,
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: cs.onSurfaceVariant),
                  ),
                ),
                // created_at
                DataCell(Text(
                  _fmtDate(row.createdAt.toInt()),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant),
                )),
                // delete action
                DataCell(
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 16, color: cs.error),
                    tooltip: 'Delete this row',
                    onPressed: () =>
                        _confirmDeleteRow(context, ref, row),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteRow(
      BuildContext context, WidgetRef ref, EmbeddingRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Embedding?'),
        content: Text(
          'Remove embedding for:\n${row.sourceId}\n\n'
          'The source content will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      try {
        await LanceDbService.deleteBySource(row.sourceId);
        ref.invalidate(
          _browserRowsProvider((filter: filter, page: page)),
        );
        ref.invalidate(_typeCountsProvider);
        ref.read(vectorDbProvider.notifier).refreshStats();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Embedding deleted'),
          ));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
          ));
        }
      }
    }
  }

  String _trunc(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;
}

class _CopyableCell extends StatelessWidget {
  final String display;
  final String full;
  final TextStyle? style;
  const _CopyableCell({required this.display, required this.full, this.style});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: full,
      child: GestureDetector(
        onTap: () => Clipboard.setData(ClipboardData(text: full)),
        child: Text(display, style: style),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge(this.type);

  static const _colors = <String, Color>{
    'vault_entry':    AppColors.brand500,
    'note':           Color(0xFF10B981),
    'idea':           Color(0xFFF59E0B),
    'document_chunk': Color(0xFF8B5CF6),
    'chat_session':   Color(0xFF06B6D4),
    'wiki_page':      AppColors.slate500,
    'audit_log':      Color(0xFFEF4444),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[type] ?? AppColors.brand500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        type.replaceAll('_', ' '),
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.2),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS (Status, Metrics, Index Management, Setup)
// ══════════════════════════════════════════════════════════════════════════════

class _StatusBanner extends StatelessWidget {
  final VectorDbState vectorDb;
  const _StatusBanner({required this.vectorDb});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (vectorDb.isInitializing) {
      return _StatusCard(
        icon: Icons.hourglass_top_rounded,
        iconColor: theme.colorScheme.primary,
        bgColor: theme.colorScheme.surfaceContainerLow,
        borderColor: theme.colorScheme.outline,
        title: 'Initialising LanceDB…',
        subtitle: 'Connecting to the Rust vector storage engine.',
        trailing: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (vectorDb.isInitialized) {
      return _StatusCard(
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.success,
        bgColor: AppColors.successSurface.withValues(alpha: 0.35),
        borderColor: AppColors.success.withValues(alpha: 0.25),
        title: 'LanceDB Active',
        subtitle: 'Rust native vector storage — high-performance ANN search',
      );
    }

    return _StatusCard(
      icon: Icons.error_outline_rounded,
      iconColor: AppColors.error,
      bgColor: AppColors.errorSurface,
      borderColor: AppColors.error.withValues(alpha: 0.3),
      title: 'LanceDB Unavailable',
      subtitle: vectorDb.error ?? 'Rust bridge could not be initialised.',
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Color borderColor;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _StatusCard({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.borderColor,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.px16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: AppSpacing.iconXl),
          const SizedBox(width: AppSpacing.px16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.px12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final VectorDbStats stats;
  final bool isLoadingStats;
  const _MetricRow({required this.stats, required this.isLoadingStats});

  @override
  Widget build(BuildContext context) {
    final hasIndex = stats.hasIndex;
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            icon: Icons.data_array_rounded,
            label: 'Embeddings',
            value: isLoadingStats ? '…' : stats.totalEmbeddings.toString(),
            color: AppColors.brand500,
          ),
        ),
        const SizedBox(width: AppSpacing.px12),
        Expanded(
          child: _MetricCard(
            icon: Icons.straighten_rounded,
            label: 'Vector Dim',
            value: stats.embeddingDim.toString(),
            color: AppColors.slate500,
          ),
        ),
        const SizedBox(width: AppSpacing.px12),
        Expanded(
          child: _MetricCard(
            icon: Icons.account_tree_rounded,
            label: 'Index',
            value: hasIndex ? 'HNSW' : 'None',
            color: hasIndex ? AppColors.success : AppColors.warning,
            subtitle: hasIndex ? 'Fast ANN search' : 'Flat scan',
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? subtitle;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.px16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.px6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(icon, size: AppSpacing.iconMd, color: color),
                ),
                const SizedBox(width: AppSpacing.px10),
                Text(label,
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: AppSpacing.px12),
            Text(value,
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _IndexManagementCard extends ConsumerWidget {
  final VectorDbState vectorDb;
  const _IndexManagementCard({required this.vectorDb});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(AppSpacing.px6),
              decoration: BoxDecoration(
                color: AppColors.brand500.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(Icons.speed_rounded,
                  size: AppSpacing.iconMd, color: AppColors.brand500),
            ),
            title: const Text('Build Vector Index'),
            subtitle: const Text(
                'Creates an HNSW index for fast ANN search. Requires ≥ 256 embeddings.'),
            trailing: vectorDb.isIndexing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant),
            onTap: vectorDb.isIndexing
                ? null
                : () => _confirmBuildIndex(context, ref),
          ),
          if (vectorDb.indexError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.px16, 0, AppSpacing.px16, AppSpacing.px8),
              child: Text(vectorDb.indexError!,
                  style: TextStyle(color: cs.error, fontSize: 12)),
            ),
          Divider(height: 1, color: cs.outline),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(AppSpacing.px6),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(Icons.sync_rounded,
                  size: AppSpacing.iconMd, color: AppColors.warning),
            ),
            title: const Text('Re-Index Everything'),
            subtitle: const Text(
                'Clears all vectors and rebuilds from scratch. May take several minutes.'),
            trailing:
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            onTap: () => _confirmReindex(context, ref),
          ),
          Divider(height: 1, color: cs.outline),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(AppSpacing.px6),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(Icons.delete_forever_rounded,
                  size: AppSpacing.iconMd, color: AppColors.error),
            ),
            title: Text('Delete All Vectors',
                style: TextStyle(color: cs.error)),
            subtitle: const Text(
                'Permanently removes all embeddings. RAG search will be unavailable until re-indexed.'),
            trailing:
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            onTap: () => _confirmDeleteAll(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBuildIndex(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(context,
        title: 'Build Vector Index?',
        body: 'Creates an HNSW index for fast ANN search at scale. '
            'Runs in the background.',
        confirmLabel: 'Build Index');
    if (ok) ref.read(vectorDbProvider.notifier).createIndex();
  }

  Future<void> _confirmReindex(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(context,
        title: 'Re-Index Everything?',
        body: 'Clears all existing LanceDB vectors and re-embeds every item. '
            'The app stays usable during indexing.',
        confirmLabel: 'Re-Index');
    if (ok && context.mounted) {
      ref.read(embeddingIndexProvider.notifier).reindexAll();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Re-indexing started in background…')));
    }
  }

  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(context,
        title: 'Delete All Vectors?',
        body: 'Permanently removes all embeddings from LanceDB. '
            'RAG search will not work until you re-index.',
        confirmLabel: 'Delete All',
        destructive: true);
    if (ok) {
      await ref.read(vectorDbProvider.notifier).deleteAll();
      ref.invalidate(_typeCountsProvider);
      ref.invalidate(_browserRowsProvider);
    }
  }

  Future<bool> _confirm(BuildContext context,
      {required String title,
      required String body,
      required String confirmLabel,
      bool destructive = false}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor:
                        Theme.of(dialogContext).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }
}

class _SetupRequiredCard extends StatelessWidget {
  final String? error;
  final VoidCallback onRetry;
  const _SetupRequiredCard({this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.px20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build_circle_outlined,
                    color: AppColors.warning, size: AppSpacing.iconXl),
                const SizedBox(width: AppSpacing.px12),
                Expanded(
                  child: Text('Rust Bridge Required',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.px12),
              Container(
                padding: const EdgeInsets.all(AppSpacing.px12),
                decoration: BoxDecoration(
                  color: AppColors.errorSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Text(error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace', color: cs.error)),
              ),
            ],
            const SizedBox(height: AppSpacing.px16),
            Text(
              'LanceDB requires the native Rust library. '
              'Run these commands once to compile and install it:',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.px12),
            _CodeBlock('''# 1. Install Rust (if not already)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 2. Run the setup script
bash scripts/setup_lance.sh

# 3. Rebuild the app
flutter pub get && flutter build macos'''),
            const SizedBox(height: AppSpacing.px16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry Connection'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Misc helpers ──────────────────────────────────────────────────────────────

class _UnavailableBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.contentPadding),
      child: _StatusCard(
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.error,
        bgColor: AppColors.errorSurface,
        borderColor: AppColors.error.withValues(alpha: 0.3),
        title: 'LanceDB Unavailable',
        subtitle: 'Switch to Overview to initialize the database.',
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: AppSpacing.px16),
            Text(title,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.px4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String error;
  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.contentPadding),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.px16),
        decoration: BoxDecoration(
          color: AppColors.errorSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
              color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: AppSpacing.iconXl),
            const SizedBox(width: AppSpacing.px12),
            Expanded(
              child: Text(error,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _DimSelector extends StatelessWidget {
  final int current;
  final WidgetRef ref;
  const _DimSelector({required this.current, required this.ref});

  static const _presets = [
    (768,  'nomic-embed-text'),
    (1024, 'mxbai-embed-large'),
    (384,  'all-MiniLM-L6-v2'),
    (4096, 'llama-embed'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.px8,
      runSpacing: AppSpacing.px8,
      children: _presets.map(((int, String) preset) {
        final (dim, model) = preset;
        return ChoiceChip(
          label: Text('$dim  —  $model'),
          selected: dim == current,
          onSelected: (_) =>
              ref.read(embeddingDimProvider.notifier).update(dim),
        );
      }).toList(),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  const _CodeBlock(this.code);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.px12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        code,
        style: const TextStyle(
            fontFamily: 'monospace', fontSize: 11, height: 1.7),
      ),
    );
  }
}
