import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/embedding_provider.dart';
import '../providers/vector_db_provider.dart';
import '../src/rust/api.dart' show VectorDbStats;
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Top-level LanceDB management screen, accessible from the sidebar.
///
/// Provides live stats, embedding-dimension configuration, index management,
/// and re-indexing controls. When the Rust bridge is unavailable, a clear
/// error card guides the user through setup — no silent SQLite fallback.
class LanceDbScreen extends ConsumerWidget {
  const LanceDbScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme    = Theme.of(context);
    final cs       = theme.colorScheme;
    final vectorDb = ref.watch(vectorDbProvider);
    final embDim   = ref.watch(embeddingDimProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LanceDB'),
        actions: [
          if (vectorDb.isInitialized)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh stats',
              onPressed: () =>
                  ref.read(vectorDbProvider.notifier).refreshStats(),
            ),
          const SizedBox(width: AppSpacing.px8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.contentPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Status / metric header ─────────────────────────────────
                _StatusHeader(vectorDb: vectorDb),
                const SizedBox(height: AppSpacing.px24),

                // ── Metric cards (only when active) ───────────────────────
                if (vectorDb.isInitialized && vectorDb.stats != null) ...[
                  _MetricRow(
                    stats: vectorDb.stats!,
                    isLoadingStats: vectorDb.isLoadingStats,
                  ),
                  const SizedBox(height: AppSpacing.px24),
                ],

                // ── Configuration ─────────────────────────────────────────
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

                // ── Storage path ──────────────────────────────────────────
                if (vectorDb.isInitialized &&
                    vectorDb.stats?.dbPath != null) ...[
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
                            child: Text(
                              vectorDb.stats!.dbPath,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // ── Index management ──────────────────────────────────────
                if (vectorDb.isInitialized) ...[
                  const SizedBox(height: AppSpacing.px24),
                  _SectionLabel('Index Management'),
                  const SizedBox(height: AppSpacing.px8),
                  _IndexManagementCard(vectorDb: vectorDb),
                ],

                // ── Error / setup ─────────────────────────────────────────
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
      ),
    );
  }
}

// ── Status header ────────────────────────────────────────────────────────────

class _StatusHeader extends StatelessWidget {
  final VectorDbState vectorDb;
  const _StatusHeader({required this.vectorDb});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (vectorDb.isInitializing) {
      return _StatusBanner(
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
      return _StatusBanner(
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.success,
        bgColor: AppColors.successSurface,
        borderColor: AppColors.success.withValues(alpha: 0.3),
        title: 'LanceDB Active',
        subtitle: 'Rust native vector storage — high-performance ANN search',
      );
    }

    return _StatusBanner(
      icon: Icons.error_outline_rounded,
      iconColor: AppColors.error,
      bgColor: AppColors.errorSurface,
      borderColor: AppColors.error.withValues(alpha: 0.3),
      title: 'LanceDB Unavailable',
      subtitle: vectorDb.error ?? 'Rust bridge could not be initialised.',
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Color borderColor;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _StatusBanner({
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

// ── Metric cards ─────────────────────────────────────────────────────────────

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

// ── Index management card ─────────────────────────────────────────────────────

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
          // Build HNSW index
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
                  style: TextStyle(
                      color: cs.error, fontSize: 12)),
            ),

          Divider(height: 1, color: cs.outline),

          // Re-index all
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
            trailing: Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant),
            onTap: () => _confirmReindex(context, ref),
          ),

          Divider(height: 1, color: cs.outline),

          // Delete all vectors
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
            trailing: Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant),
            onTap: () => _confirmDeleteAll(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBuildIndex(
      BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Build Vector Index?',
      body: 'Creates an HNSW index that makes similarity search much faster '
          'at scale. The process runs in the background.',
      confirmLabel: 'Build Index',
    );
    if (ok) ref.read(vectorDbProvider.notifier).createIndex();
  }

  Future<void> _confirmReindex(
      BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Re-Index Everything?',
      body: 'Clears all existing LanceDB vectors and re-embeds every item. '
          'The app stays usable during indexing.',
      confirmLabel: 'Re-Index',
    );
    if (ok && context.mounted) {
      ref.read(embeddingIndexProvider.notifier).reindexAll();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Re-indexing started in background…')),
      );
    }
  }

  Future<void> _confirmDeleteAll(
      BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Delete All Vectors?',
      body: 'Permanently removes all embeddings from LanceDB. '
          'RAG search will not work until you re-index.',
      confirmLabel: 'Delete All',
      destructive: true,
    );
    if (ok) await ref.read(vectorDbProvider.notifier).deleteAll();
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }
}

// ── Setup required card ───────────────────────────────────────────────────────

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
            Row(
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry Connection'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

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
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.7),
      ),
    );
  }
}
