import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../models/vault_entry.dart';
import '../providers/ai_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/documents_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/vault_provider.dart';
import '../services/ai_service.dart';
import '../widgets/ai_search_bar.dart';
import 'document_form_screen.dart';
import 'documents_list_screen.dart';
import 'entry_form_screen.dart';
import 'note_form_screen.dart';
import 'notes_list_screen.dart';
import 'ollama_screen.dart';
import 'settings_screen.dart';
import 'categories_screen.dart';
import 'expired_secrets_screen.dart';
import 'vault_list_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _fabOpen = false;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(vaultEntriesProvider);
    final notesAsync = ref.watch(notesProvider);
    final docsAsync = ref.watch(documentsProvider);
    final aiService = ref.watch(aiServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      body: Stack(
        children: [
          entriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (entries) {
              final notes = notesAsync.valueOrNull ?? [];
              final docCount = docsAsync.valueOrNull?.length ?? 0;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // AI Search bar
                        const AiChatWidget(),
                        const SizedBox(height: 16),

                        // Stats cards row
                        _StatsRow(
                          entries: entries,
                          notes: notes,
                          documentCount: docCount,
                          aiService: aiService,
                        ),
                        const SizedBox(height: 24),

                        // Upcoming expirations
                        _ExpiringSecretsSection(entries: entries),
                        const SizedBox(height: 24),

                        // Recently updated
                        _RecentSecretsSection(entries: entries),
                        // Extra padding so FAB doesn't cover content
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // Scrim overlay when FAB menu is open
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _fabOpen = false),
                child: Container(
                  color: Colors.black54,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _buildSpeedDial(context),
    );
  }

  Widget _buildSpeedDial(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Menu items (visible when open)
        if (_fabOpen) ...[
          _SpeedDialItem(
            icon: Icons.key,
            label: 'Add Secret',
            onTap: () {
              setState(() => _fabOpen = false);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const EntryFormScreen()),
              );
            },
            theme: theme,
          ),
          const SizedBox(height: 12),
          _SpeedDialItem(
            icon: Icons.note_add,
            label: 'New Note',
            onTap: () {
              setState(() => _fabOpen = false);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NoteFormScreen()),
              );
            },
            theme: theme,
          ),
          const SizedBox(height: 12),
          _SpeedDialItem(
            icon: Icons.description,
            label: 'Add Document',
            onTap: () {
              setState(() => _fabOpen = false);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DocumentFormScreen()),
              );
            },
            theme: theme,
          ),
          const SizedBox(height: 16),
        ],
        // Main FAB
        FloatingActionButton(
          onPressed: () => setState(() => _fabOpen = !_fabOpen),
          child: AnimatedRotation(
            turns: _fabOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add, size: 28),
          ),
        ),
      ],
    );
  }
}

/// Speed dial menu item
class _SpeedDialItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ThemeData theme;

  const _SpeedDialItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}

/// Top row of stat cards
class _StatsRow extends StatefulWidget {
  final List<VaultEntry> entries;
  final List<Note> notes;
  final int documentCount;
  final dynamic aiService;

  const _StatsRow({
    required this.entries,
    required this.notes,
    required this.documentCount,
    required this.aiService,
  });

  @override
  State<_StatsRow> createState() => _StatsRowState();
}

class _StatsRowState extends State<_StatsRow> {
  OllamaStatus? _ollamaStatus;

  @override
  void initState() {
    super.initState();
    _checkOllama();
  }

  @override
  void didUpdateWidget(covariant _StatsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aiService != widget.aiService) {
      _checkOllama();
    }
  }

  Future<void> _checkOllama() async {
    setState(() => _ollamaStatus = null);
    final status = await widget.aiService.checkStatus();
    if (mounted) {
      setState(() => _ollamaStatus = status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final totalSecrets = entries.length;
    final expiredCount = entries.where((e) => e.isExpired).length;
    final expiringSoonCount = entries.where((e) => e.isExpiringSoon).length;

    // Category breakdown
    final categories = <String, int>{};
    for (final entry in entries) {
      categories[entry.category] = (categories[entry.category] ?? 0) + 1;
    }

    final noteCount = widget.notes.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: constraints.maxWidth > 600 ? 2.2 : 1.3,
          children: [
            _DashboardCard(
              icon: Icons.shield,
              iconColor: Colors.indigo,
              label: 'Secrets',
              value: '$totalSecrets',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VaultListScreen()),
              ),
            ),
            _DashboardCard(
              icon: Icons.note,
              iconColor: Colors.amber.shade700,
              label: 'Notes',
              value: '$noteCount',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotesListScreen()),
              ),
            ),
            _DashboardCard(
              icon: Icons.description,
              iconColor: Colors.deepPurple,
              label: 'Documents',
              value: '${widget.documentCount}',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DocumentsListScreen()),
              ),
            ),
            _DashboardCard(
              icon: Icons.warning_amber,
              iconColor: expiredCount > 0 ? Colors.red : Colors.green,
              label: 'Expired',
              value: '$expiredCount',
              subtitle: expiringSoonCount > 0
                  ? '$expiringSoonCount expiring soon'
                  : null,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ExpiredSecretsScreen()),
              ),
            ),
            _DashboardCard(
              icon: Icons.category,
              iconColor: Colors.teal,
              label: 'Categories',
              value: '${categories.length}',
              subtitle: categories.entries
                  .take(3)
                  .map((e) => '${e.key}: ${e.value}')
                  .join(', '),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CategoriesScreen()),
              ),
            ),
            _OllamaStatusCard(
              status: _ollamaStatus,
              modelName: widget.aiService.model,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const OllamaScreen()),
                );
                // Refresh status when returning from Ollama screen
                _checkOllama();
              },
            ),
          ],
        );
      },
    );
  }
}

/// Individual dashboard stat card
class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;

  const _DashboardCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  if (onTap != null)
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ollama connection status card — taps navigate to full Ollama management
class _OllamaStatusCard extends ConsumerWidget {
  final OllamaStatus? status;
  final String modelName;
  final VoidCallback onTap;

  const _OllamaStatusCard({
    required this.status,
    required this.modelName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final downloadState = ref.watch(modelDownloadProvider);
    final isDownloading = downloadState.isDownloading;

    final Color statusColor;
    final IconData statusIcon;
    final String statusText;
    final String subtitleText;

    if (isDownloading) {
      statusColor = Colors.blue;
      statusIcon = Icons.downloading;
      statusText = 'Downloading...';
      subtitleText = downloadState.modelName ?? '';
    } else if (status == null) {
      statusColor = Colors.grey;
      statusIcon = Icons.sync;
      statusText = 'Checking...';
      subtitleText = modelName;
    } else {
      switch (status!.status) {
        case OllamaConnectionStatus.ready:
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
          statusText = 'Ready';
          subtitleText = modelName;
        case OllamaConnectionStatus.ollamaNotRunning:
          statusColor = Colors.red;
          statusIcon = Icons.error;
          statusText = 'Not Running';
          subtitleText = 'Tap to configure';
        case OllamaConnectionStatus.modelNotFound:
          statusColor = Colors.orange;
          statusIcon = Icons.warning;
          statusText = 'Model Missing';
          subtitleText = 'Tap to configure';
      }
    }

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.smart_toy, color: statusColor, size: 24),
                  if (isDownloading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.5),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const Spacer(),
              if (isDownloading && downloadState.progress != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: downloadState.progress,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Row(
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      statusText,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              Text(
                subtitleText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section showing secrets that are expired or expiring soon
class _ExpiringSecretsSection extends StatelessWidget {
  final List<VaultEntry> entries;

  const _ExpiringSecretsSection({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Get expired + expiring soon entries, sorted by expiry date
    final expiring = entries
        .where((e) => e.expiresAt != null && (e.isExpired || e.isExpiringSoon))
        .toList()
      ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));

    // Also show upcoming (next 90 days) that aren't in "soon" range
    final upcoming = entries
        .where((e) =>
            e.expiresAt != null &&
            !e.isExpired &&
            !e.isExpiringSoon &&
            e.expiresAt!.isBefore(
                DateTime.now().add(const Duration(days: 90))))
        .toList()
      ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));

    final allUpcoming = [...expiring, ...upcoming].take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Upcoming Expirations',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (allUpcoming.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 40,
                      color: Colors.green.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No upcoming expirations',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: allUpcoming.map((entry) {
                return _ExpiryListItem(entry: entry);
              }).toList(),
            ),
          ),
      ],
    );
  }
}

/// Single expiring entry row
class _ExpiryListItem extends StatelessWidget {
  final VaultEntry entry;

  const _ExpiryListItem({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiresAt = entry.expiresAt!;
    final daysLeft = expiresAt.difference(DateTime.now()).inDays;

    final Color statusColor;
    final String statusLabel;

    if (entry.isExpired) {
      statusColor = theme.colorScheme.error;
      final daysAgo = DateTime.now().difference(expiresAt).inDays;
      statusLabel = 'Expired ${daysAgo}d ago';
    } else if (entry.isExpiringSoon) {
      statusColor = Colors.orange;
      statusLabel = '${daysLeft}d left';
    } else {
      statusColor = theme.colorScheme.onSurfaceVariant;
      statusLabel = '${daysLeft}d left';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.15),
        child: Icon(
          entry.isExpired ? Icons.error : Icons.schedule,
          color: statusColor,
          size: 20,
        ),
      ),
      title: Text(
        entry.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${entry.category} \u2022 Expires ${expiresAt.year}-${expiresAt.month.toString().padLeft(2, '0')}-${expiresAt.day.toString().padLeft(2, '0')}',
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          statusLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: statusColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EntryFormScreen(entry: entry),
        ),
      ),
    );
  }
}

/// Section showing recently added/updated secrets
class _RecentSecretsSection extends StatelessWidget {
  final List<VaultEntry> entries;

  const _RecentSecretsSection({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final recent = [...entries]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final top5 = recent.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Recently Updated',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VaultListScreen()),
              ),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (top5.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No secrets yet. Tap + to add one.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: top5.map((entry) {
                final date = entry.updatedAt;
                final dateStr =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        theme.colorScheme.primaryContainer,
                    child: Icon(
                      _categoryIcon(entry.category),
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    entry.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${entry.category} \u2022 $dateStr',
                  ),
                  trailing: entry.isExpired
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'EXPIRED',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EntryFormScreen(entry: entry),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'login':
        return Icons.login;
      case 'api key':
        return Icons.key;
      case 'credit card':
        return Icons.credit_card;
      case 'ssh key':
        return Icons.terminal;
      case 'wifi':
        return Icons.wifi;
      default:
        return Icons.lock;
    }
  }
}
