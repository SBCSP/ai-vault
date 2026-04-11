import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/embedding_provider.dart';
import '../providers/vector_db_provider.dart';
import '../services/lance_db_service.dart';

class VectorDbSettingsScreen extends ConsumerWidget {
  const VectorDbSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vectorDb = ref.watch(vectorDbProvider);
    final embeddingDim = ref.watch(embeddingDimProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vector Database'),
        actions: [
          if (vectorDb.isInitialized)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh stats',
              onPressed: () =>
                  ref.read(vectorDbProvider.notifier).refreshStats(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status banner ────────────────────────────────────────────────
          _StatusBanner(vectorDb: vectorDb),
          const SizedBox(height: 20),

          // ── Backend info card ────────────────────────────────────────────
          _SectionHeader('Backend'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    label: 'Engine',
                    value: vectorDb.isInitialized ? 'LanceDB (Rust)' : 'SQLite (fallback)',
                    valueColor: vectorDb.isInitialized
                        ? Colors.green.shade700
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    label: 'Storage',
                    value: vectorDb.isInitialized
                        ? (vectorDb.stats?.dbPath ?? '…')
                        : 'app_support/ai_vault.db (Embeddings table)',
                  ),
                  if (vectorDb.isInitialized) ...[
                    const Divider(height: 24),
                    _InfoRow(
                      label: 'Embedding dim',
                      value: '${vectorDb.stats?.embeddingDim ?? embeddingDim}',
                    ),
                    const Divider(height: 24),
                    _InfoRow(
                      label: 'Vector index',
                      value: (vectorDb.stats?.hasIndex ?? false)
                          ? 'HNSW (IVF-PQ) — fast ANN'
                          : 'None — flat brute-force scan',
                      valueColor: (vectorDb.stats?.hasIndex ?? false)
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Stats card ───────────────────────────────────────────────────
          if (vectorDb.isInitialized) ...[
            const SizedBox(height: 20),
            _SectionHeader('Statistics'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: vectorDb.isLoadingStats
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : vectorDb.stats == null
                        ? const Text('No stats available.')
                        : _StatsGrid(stats: vectorDb.stats!),
              ),
            ),
          ],

          // ── Config card ──────────────────────────────────────────────────
          const SizedBox(height: 20),
          _SectionHeader('Configuration'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Embedding Dimension',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Must match your embedding model. Changing this requires a full re-index.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DimSelector(current: embeddingDim, ref: ref),
                ],
              ),
            ),
          ),

          // ── Actions card ─────────────────────────────────────────────────
          if (vectorDb.isInitialized) ...[
            const SizedBox(height: 20),
            _SectionHeader('Actions'),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  // Build HNSW index
                  ListTile(
                    leading: const Icon(Icons.speed),
                    title: const Text('Build Vector Index'),
                    subtitle: const Text(
                        'Creates HNSW index for fast ANN search. Requires ≥ 256 embeddings.'),
                    trailing: vectorDb.isIndexing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: vectorDb.isIndexing
                        ? null
                        : () => _buildIndex(context, ref),
                  ),
                  if (vectorDb.indexError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        vectorDb.indexError!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  // Re-index all
                  ListTile(
                    leading: const Icon(Icons.sync),
                    title: const Text('Re-Index Everything'),
                    subtitle: const Text(
                        'Clears all vectors and rebuilds from scratch. May take several minutes.'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _reindexAll(context, ref),
                  ),
                  const Divider(height: 1),
                  // Delete all
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Delete All Vectors',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    subtitle: const Text(
                        'Permanently removes all embeddings from LanceDB.'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _deleteAll(context, ref),
                  ),
                ],
              ),
            ),
          ],

          // ── Setup instructions ───────────────────────────────────────────
          if (!vectorDb.isInitialized) ...[
            const SizedBox(height: 20),
            _SetupCard(onRetry: () =>
                ref.read(vectorDbProvider.notifier).reinitialize()),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _buildIndex(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Build Vector Index?'),
        content: const Text(
          'This creates an HNSW index that makes similarity search much faster at scale. '
          'The process runs in the background and may take a moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Build Index'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(vectorDbProvider.notifier).createIndex();
    }
  }

  Future<void> _reindexAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Re-Index Everything?'),
        content: const Text(
          'This clears all existing LanceDB vectors and re-embeds all items. '
          'The app remains usable during indexing. This may take several minutes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Re-Index'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ref.read(embeddingIndexProvider.notifier).reindexAll();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Re-indexing started in background…')),
      );
    }
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete All Vectors?'),
        content: const Text(
          'This permanently removes all embeddings from LanceDB. '
          'RAG search will not work until you re-index.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(vectorDbProvider.notifier).deleteAll();
    }
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final VectorDbState vectorDb;
  const _StatusBanner({required this.vectorDb});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (vectorDb.isInitializing) {
      return _Banner(
        color: theme.colorScheme.surfaceContainerHigh,
        icon: Icons.hourglass_top,
        iconColor: theme.colorScheme.primary,
        title: 'Initialising LanceDB…',
        subtitle: null,
      );
    }

    if (vectorDb.isInitialized) {
      return _Banner(
        color: Colors.green.withValues(alpha: 0.12),
        icon: Icons.check_circle,
        iconColor: Colors.green.shade700,
        title: 'LanceDB Active',
        subtitle:
            '${vectorDb.stats?.totalEmbeddings ?? 0} embeddings stored in Rust native storage',
      );
    }

    return _Banner(
      color: Colors.orange.withValues(alpha: 0.12),
      icon: Icons.warning_amber,
      iconColor: Colors.orange.shade700,
      title: 'SQLite Fallback Mode',
      subtitle: 'Rust bridge not available — using in-memory cosine search',
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;

  const _Banner({
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final VectorDbStats stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _StatChip(
          label: 'Embeddings',
          value: stats.totalEmbeddings.toString(),
          icon: Icons.data_array,
        ),
        _StatChip(
          label: 'Vector Dim',
          value: stats.embeddingDim.toString(),
          icon: Icons.straighten,
        ),
        _StatChip(
          label: 'Index',
          value: stats.hasIndex ? 'HNSW' : 'None',
          icon: Icons.account_tree,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text(label,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DimSelector extends StatelessWidget {
  final int current;
  final WidgetRef ref;

  const _DimSelector({required this.current, required this.ref});

  static const _dims = [
    (768, 'nomic-embed-text'),
    (1024, 'mxbai-embed-large'),
    (384, 'all-MiniLM-L6-v2'),
    (4096, 'llama-embed'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _dims.map((entry) {
        final (dim, model) = entry;
        final selected = dim == current;
        return ChoiceChip(
          label: Text('$dim — $model'),
          selected: selected,
          onSelected: (_) =>
              ref.read(embeddingDimProvider.notifier).update(dim),
        );
      }).toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _SetupCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _SetupCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.build_circle_outlined),
                const SizedBox(width: 8),
                Text('Setup Required',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Run these commands once to compile the Rust bridge:',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _CodeBlock('''# 1. Install Rust (if not already)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 2. Run the setup script
bash scripts/setup_lance.sh

# 3. Rebuild the app
flutter pub get && flutter build macos'''),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry Connection'),
            ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        code,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
        ),
      ),
    );
  }
}
