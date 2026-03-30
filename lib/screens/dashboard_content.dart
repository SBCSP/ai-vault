import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart' hide VaultEntry;
import '../models/vault_entry.dart';
import '../providers/ai_provider.dart';
import '../providers/chat_history_provider.dart';
import '../providers/documents_provider.dart';
import '../providers/ideas_provider.dart';
import '../providers/metrics_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/secrets_lock_provider.dart';
import '../providers/server_provider.dart';
import '../providers/vault_provider.dart';
import '../services/ai_service.dart';
import 'document_form_screen.dart';
import 'entry_form_screen.dart';
import 'idea_form_screen.dart';
import 'note_form_screen.dart';

/// Timeseries-based metrics dashboard.
class DashboardContent extends ConsumerStatefulWidget {
  const DashboardContent({super.key});

  @override
  ConsumerState<DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends ConsumerState<DashboardContent> {
  bool _fabOpen = false;
  int _chartDays = 30;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(vaultEntriesProvider);
    final notesAsync = ref.watch(notesProvider);
    final ideasAsync = ref.watch(ideasProvider);
    final docsAsync = ref.watch(documentsProvider);
    final chatsAsync = ref.watch(chatSessionsProvider);
    final serversAsync = ref.watch(serversProvider);
    final aiService = ref.watch(aiServiceProvider);
    final metricsAsync = ref.watch(metricsTimeseriesProvider(_chartDays));
    final activityAsync = ref.watch(activityTimeseriesProvider(_chartDays));
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          entriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (entries) {
              final notes = notesAsync.valueOrNull ?? [];
              final ideaCount = ideasAsync.valueOrNull?.length ?? 0;
              final docCount = docsAsync.valueOrNull?.length ?? 0;
              final chatCount = chatsAsync.valueOrNull?.length ?? 0;
              final serverCount = serversAsync.valueOrNull?.length ?? 0;
              final expiredCount = entries.where((e) => e.isExpired).length;
              final expiringSoonCount =
                  entries.where((e) => e.isExpiringSoon).length;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // --- Summary cards row ---
                        _SummaryRow(
                          secrets: entries.length,
                          notes: notes.length,
                          ideas: ideaCount,
                          documents: docCount,
                          chats: chatCount,
                          servers: serverCount,
                          expired: expiredCount,
                          expiringSoon: expiringSoonCount,
                        ),
                        const SizedBox(height: 16),

                        // --- LLM Status ---
                        _LlmStatusRow(aiService: aiService),
                        const SizedBox(height: 24),

                        // --- Charts ---
                        _buildChartHeader(theme),
                        const SizedBox(height: 12),
                        metricsAsync.when(
                          loading: () => const SizedBox(
                            height: 250,
                            child:
                                Center(child: CircularProgressIndicator()),
                          ),
                          error: (e, _) =>
                              Center(child: Text('Chart error: $e')),
                          data: (metrics) => Column(
                            children: [
                              _TimeseriesChart(
                                title: 'Vault Items',
                                metrics: metrics,
                                series: [
                                  _Series('Secrets', Colors.indigo,
                                      (m) => m.secretsCount),
                                  _Series('Notes', Colors.amber.shade700,
                                      (m) => m.notesCount),
                                  _Series('Ideas', Colors.orange.shade600,
                                      (m) => m.ideasCount),
                                  _Series('Documents', Colors.deepPurple,
                                      (m) => m.documentsCount),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _TimeseriesChart(
                                title: 'Activity',
                                metrics: metrics,
                                series: [
                                  _Series('Chats', Colors.cyan.shade700,
                                      (m) => m.chatsCount),
                                  _Series('Servers', Colors.blueGrey,
                                      (m) => m.serversCount),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _TimeseriesChart(
                                title: 'Secret Health',
                                metrics: metrics,
                                series: [
                                  _Series('Expired', Colors.red,
                                      (m) => m.expiredCount),
                                  _Series(
                                      'Expiring Soon',
                                      Colors.orange,
                                      (m) => m.expiringSoonCount),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // --- Activity Charts (audit-derived) ---
                        activityAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (e, _) =>
                              Center(child: Text('Activity error: $e')),
                          data: (activity) => Column(
                            children: [
                              _ActivityChart(
                                title: 'Daily Activity',
                                activity: activity,
                                series: [
                                  _ActivitySeries('Total Events',
                                      Colors.indigo, (a) => a.totalEvents),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _ActivityChart(
                                title: 'CRUD Operations',
                                activity: activity,
                                series: [
                                  _ActivitySeries('Creates',
                                      Colors.green.shade600, (a) => a.creates),
                                  _ActivitySeries('Updates',
                                      Colors.blue.shade600, (a) => a.updates),
                                  _ActivitySeries('Deletes', Colors.red.shade600,
                                      (a) => a.deletes),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _ActivityChart(
                                title: 'Security Events',
                                activity: activity,
                                series: [
                                  _ActivitySeries(
                                      'Unlocks', Colors.green, (a) => a.unlocks),
                                  _ActivitySeries('Failed Unlocks',
                                      Colors.red.shade400, (a) => a.unlockFailures),
                                  _ActivitySeries(
                                      'Locks', Colors.blueGrey, (a) => a.locks),
                                  _ActivitySeries('Secrets Lock',
                                      Colors.purple, (a) => a.secretsLockEvents),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _ActivityChart(
                                title: 'AI & MCP Usage',
                                activity: activity,
                                series: [
                                  _ActivitySeries('Chat Saves',
                                      Colors.cyan.shade700, (a) => a.chatSaves),
                                  _ActivitySeries('MCP Tool Calls',
                                      Colors.teal, (a) => a.mcpToolCalls),
                                  _ActivitySeries('MCP Failures',
                                      Colors.red, (a) => a.mcpToolFailures),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _ActivityChart(
                                title: 'Infrastructure',
                                activity: activity,
                                series: [
                                  _ActivitySeries('Settings Changes',
                                      Colors.amber.shade700, (a) => a.settingsChanges),
                                  _ActivitySeries('Indexing Ops',
                                      Colors.deepPurple, (a) => a.indexingOps),
                                  _ActivitySeries(
                                      'AWS Ops', Colors.orange, (a) => a.awsOps),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // --- Expiring secrets ---
                        _ExpiringSecretsSection(entries: entries),
                        const SizedBox(height: 24),

                        // --- Recent secrets ---
                        _RecentSecretsSection(entries: entries),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _fabOpen = false),
                child: Container(color: Colors.black54),
              ),
            ),
        ],
      ),
      floatingActionButton: _buildSpeedDial(context),
    );
  }

  Widget _buildChartHeader(ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.show_chart, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          'Trends',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: 'Refresh dashboard',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            ref.invalidate(metricsTimeseriesProvider(_chartDays));
            ref.invalidate(activityTimeseriesProvider(_chartDays));
          },
        ),
        const Spacer(),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7d')),
            ButtonSegment(value: 30, label: Text('30d')),
            ButtonSegment(value: 90, label: Text('90d')),
          ],
          selected: {_chartDays},
          onSelectionChanged: (s) => setState(() => _chartDays = s.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(
              theme.textTheme.labelSmall,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedDial(BuildContext context) {
    final theme = Theme.of(context);
    final secretsLocked = ref.watch(secretsLockProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabOpen) ...[
          if (!secretsLocked) ...[
            _SpeedDialItem(
              icon: Icons.key,
              label: 'Add Secret',
              onTap: () {
                setState(() => _fabOpen = false);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const EntryFormScreen()));
              },
              theme: theme,
            ),
            const SizedBox(height: 12),
          ],
          _SpeedDialItem(
            icon: Icons.note_add,
            label: 'New Note',
            onTap: () {
              setState(() => _fabOpen = false);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NoteFormScreen()));
            },
            theme: theme,
          ),
          const SizedBox(height: 12),
          _SpeedDialItem(
            icon: Icons.lightbulb,
            label: 'New Idea',
            onTap: () {
              setState(() => _fabOpen = false);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const IdeaFormScreen()));
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
                      builder: (_) => const DocumentFormScreen()));
            },
            theme: theme,
          ),
          const SizedBox(height: 16),
        ],
        FloatingActionButton(
          onPressed: () => setState(() => _fabOpen = !_fabOpen),
          child: AnimatedRotation(
            turns: _fabOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.menu_open, size: 28),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// Summary Cards Row
// ──────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final int secrets, notes, ideas, documents, chats, servers;
  final int expired, expiringSoon;

  const _SummaryRow({
    required this.secrets,
    required this.notes,
    required this.ideas,
    required this.documents,
    required this.chats,
    required this.servers,
    required this.expired,
    required this.expiringSoon,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cardWidth = constraints.maxWidth > 700
          ? (constraints.maxWidth - 42) / 4
          : (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _SummaryCard(width: cardWidth, icon: Icons.shield, color: Colors.indigo, label: 'Secrets', value: secrets),
          _SummaryCard(width: cardWidth, icon: Icons.note, color: Colors.amber.shade700, label: 'Notes', value: notes),
          _SummaryCard(width: cardWidth, icon: Icons.lightbulb, color: Colors.orange.shade600, label: 'Ideas', value: ideas),
          _SummaryCard(width: cardWidth, icon: Icons.description, color: Colors.deepPurple, label: 'Documents', value: documents),
          _SummaryCard(width: cardWidth, icon: Icons.chat_bubble_outline, color: Colors.cyan.shade700, label: 'Chats', value: chats),
          _SummaryCard(width: cardWidth, icon: Icons.dns, color: Colors.blueGrey, label: 'Servers', value: servers),
          _SummaryCard(
            width: cardWidth,
            icon: Icons.warning_amber,
            color: expired > 0 ? Colors.red : Colors.green,
            label: 'Expired',
            value: expired,
            subtitle: expiringSoon > 0 ? '$expiringSoon expiring soon' : null,
          ),
        ],
      );
    });
  }
}

class _SummaryCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final Color color;
  final String label;
  final int value;
  final String? subtitle;

  const _SummaryCard({
    required this.width,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '$value',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Timeseries Line Chart
// ──────────────────────────────────────────────

class _Series {
  final String name;
  final Color color;
  final int Function(DailyMetric) getter;

  const _Series(this.name, this.color, this.getter);
}

class _TimeseriesChart extends StatelessWidget {
  final String title;
  final List<DailyMetric> metrics;
  final List<_Series> series;

  const _TimeseriesChart({
    required this.title,
    required this.metrics,
    required this.series,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (metrics.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No data yet — metrics are recorded daily.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    // Build spots for each series
    final lineBars = <LineChartBarData>[];
    double maxY = 0;

    for (final s in series) {
      final spots = <FlSpot>[];
      for (var i = 0; i < metrics.length; i++) {
        final val = s.getter(metrics[i]).toDouble();
        if (val > maxY) maxY = val;
        spots.add(FlSpot(i.toDouble(), val));
      }
      lineBars.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.2,
        color: s.color,
        barWidth: 2.5,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: metrics.length <= 14,
          getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
            radius: 3,
            color: s.color,
            strokeWidth: 0,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          color: s.color.withValues(alpha: 0.08),
        ),
      ));
    }

    // Ensure some headroom
    maxY = maxY < 1 ? 1 : (maxY * 1.15).ceilToDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Legend
                ...series.map((s) => Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 3,
                            decoration: BoxDecoration(
                              color: s.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            s.name,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  lineBarsData: lineBars,
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY > 5 ? (maxY / 4).roundToDouble().clamp(1, double.infinity) : 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.3),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: maxY > 5 ? (maxY / 4).roundToDouble().clamp(1, double.infinity) : 1,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max || value < 0) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            value.toInt().toString(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: _bottomInterval(metrics.length),
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= metrics.length) {
                            return const SizedBox.shrink();
                          }
                          final date = metrics[idx].date;
                          // Show as MM/DD
                          final parts = date.split('-');
                          final label = '${parts[1]}/${parts[2]}';
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 9,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) {
                        return spots.map((spot) {
                          final s = series[spot.barIndex];
                          return LineTooltipItem(
                            '${s.name}: ${spot.y.toInt()}',
                            TextStyle(
                              color: s.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _bottomInterval(int count) {
    if (count <= 7) return 1;
    if (count <= 14) return 2;
    if (count <= 30) return 5;
    return 10;
  }
}

// ──────────────────────────────────────────────
// Activity Timeseries Chart (audit-derived)
// ──────────────────────────────────────────────

class _ActivitySeries {
  final String name;
  final Color color;
  final int Function(DailyActivity) getter;

  const _ActivitySeries(this.name, this.color, this.getter);
}

class _ActivityChart extends StatelessWidget {
  final String title;
  final List<DailyActivity> activity;
  final List<_ActivitySeries> series;

  const _ActivityChart({
    required this.title,
    required this.activity,
    required this.series,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (activity.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No activity data yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    final lineBars = <LineChartBarData>[];
    double maxY = 0;

    for (final s in series) {
      final spots = <FlSpot>[];
      for (var i = 0; i < activity.length; i++) {
        final val = s.getter(activity[i]).toDouble();
        if (val > maxY) maxY = val;
        spots.add(FlSpot(i.toDouble(), val));
      }
      lineBars.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.2,
        color: s.color,
        barWidth: 2.5,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: activity.length <= 14,
          getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
            radius: 3,
            color: s.color,
            strokeWidth: 0,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          color: s.color.withValues(alpha: 0.08),
        ),
      ));
    }

    maxY = maxY < 1 ? 1 : (maxY * 1.15).ceilToDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ...series.map((s) => Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 3,
                            decoration: BoxDecoration(
                              color: s.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            s.name,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  lineBarsData: lineBars,
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY > 5
                        ? (maxY / 4).roundToDouble().clamp(1, double.infinity)
                        : 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.3),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: maxY > 5
                            ? (maxY / 4)
                                .roundToDouble()
                                .clamp(1, double.infinity)
                            : 1,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max || value < 0) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            value.toInt().toString(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: _bottomInterval(activity.length),
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= activity.length) {
                            return const SizedBox.shrink();
                          }
                          final date = activity[idx].date;
                          final parts = date.split('-');
                          final label = '${parts[1]}/${parts[2]}';
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 9,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) {
                        return spots.map((spot) {
                          final s = series[spot.barIndex];
                          return LineTooltipItem(
                            '${s.name}: ${spot.y.toInt()}',
                            TextStyle(
                              color: s.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _bottomInterval(int count) {
    if (count <= 7) return 1;
    if (count <= 14) return 2;
    if (count <= 30) return 5;
    return 10;
  }
}

// ──────────────────────────────────────────────
// Ollama Status Row
// ──────────────────────────────────────────────

class _LlmStatusRow extends ConsumerStatefulWidget {
  final dynamic aiService;

  const _LlmStatusRow({required this.aiService});

  @override
  ConsumerState<_LlmStatusRow> createState() => _LlmStatusRowState();
}

class _LlmStatusRowState extends ConsumerState<_LlmStatusRow> {
  OllamaStatus? _ollamaStatus;

  @override
  void initState() {
    super.initState();
    _checkOllama();
  }

  @override
  void didUpdateWidget(covariant _LlmStatusRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aiService != widget.aiService) _checkOllama();
  }

  Future<void> _checkOllama() async {
    setState(() => _ollamaStatus = null);
    final status = await widget.aiService.checkStatus();
    if (mounted) setState(() => _ollamaStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final llmProvider = ref.watch(llmProviderTypeProvider);
    final isUsingClaude = llmProvider == LlmProviderType.claude;
    final downloadState = ref.watch(modelDownloadProvider);
    final isDownloading = downloadState.isDownloading;

    final Color statusColor;
    final String statusText;
    final IconData statusIcon;
    final String providerLabel;

    if (isUsingClaude) {
      // Claude API — check if API key is configured
      final claudeService = ref.watch(claudeApiProvider);
      final hasKey = claudeService.apiKey.isNotEmpty;
      providerLabel = 'Claude API';
      if (hasKey) {
        statusColor = Colors.green;
        statusText = '$providerLabel Ready — ${claudeService.model}';
        statusIcon = Icons.check_circle;
      } else {
        statusColor = Colors.orange;
        statusText = '$providerLabel — No API key configured';
        statusIcon = Icons.warning;
      }
    } else {
      // Ollama — check connection status
      providerLabel = 'Ollama';
      if (isDownloading) {
        statusColor = Colors.blue;
        statusText = '$providerLabel — Downloading ${downloadState.modelName ?? ''}...';
        statusIcon = Icons.downloading;
      } else if (_ollamaStatus == null) {
        statusColor = Colors.grey;
        statusText = '$providerLabel — Checking connection...';
        statusIcon = Icons.sync;
      } else {
        switch (_ollamaStatus!.status) {
          case OllamaConnectionStatus.ready:
            statusColor = Colors.green;
            statusText = '$providerLabel Ready — ${widget.aiService.model}';
            statusIcon = Icons.check_circle;
          case OllamaConnectionStatus.ollamaNotRunning:
            statusColor = Colors.red;
            statusText = '$providerLabel — Not Running';
            statusIcon = Icons.error;
          case OllamaConnectionStatus.modelNotFound:
            statusColor = Colors.orange;
            statusText = '$providerLabel — Model Not Found';
            statusIcon = Icons.warning;
        }
      }
    }

    return Card(
      elevation: 0,
      color: statusColor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              isUsingClaude ? Icons.cloud : Icons.smart_toy,
              color: statusColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Icon(statusIcon, color: statusColor, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                statusText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!isUsingClaude &&
                isDownloading &&
                downloadState.progress != null)
              SizedBox(
                width: 100,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: downloadState.progress,
                    minHeight: 4,
                  ),
                ),
              ),
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 8),
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
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Speed Dial
// ──────────────────────────────────────────────

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

// ──────────────────────────────────────────────
// Expiring Secrets
// ──────────────────────────────────────────────

class _ExpiringSecretsSection extends StatelessWidget {
  final List<VaultEntry> entries;

  const _ExpiringSecretsSection({required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final expiring = entries
        .where((e) => e.expiresAt != null && (e.isExpired || e.isExpiringSoon))
        .toList()
      ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));

    final upcoming = entries
        .where((e) =>
            e.expiresAt != null &&
            !e.isExpired &&
            !e.isExpiringSoon &&
            e.expiresAt!
                .isBefore(DateTime.now().add(const Duration(days: 90))))
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
                    Icon(Icons.check_circle_outline,
                        size: 40,
                        color: Colors.green.withValues(alpha: 0.7)),
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
              children: allUpcoming
                  .map((entry) => _ExpiryListItem(entry: entry))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

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
      title: Text(entry.title,
          style: const TextStyle(fontWeight: FontWeight.w600)),
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
    );
  }
}

// ──────────────────────────────────────────────
// Recent Secrets
// ──────────────────────────────────────────────

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
        const SizedBox(height: 8),
        if (top5.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No secrets yet. Use the + button to add one.',
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
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      _categoryIcon(entry.category),
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(entry.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${entry.category} \u2022 $dateStr'),
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
