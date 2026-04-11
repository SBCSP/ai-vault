import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/linear_provider.dart';

class LinearSettingsScreen extends ConsumerStatefulWidget {
  const LinearSettingsScreen({super.key});

  @override
  ConsumerState<LinearSettingsScreen> createState() =>
      _LinearSettingsScreenState();
}

class _LinearSettingsScreenState
    extends ConsumerState<LinearSettingsScreen> {
  late final TextEditingController _clientIdCtrl;
  late final TextEditingController _clientSecretCtrl;
  bool _secretObscured = true;

  @override
  void initState() {
    super.initState();
    final linear = ref.read(linearProvider);
    _clientIdCtrl = TextEditingController(text: linear.clientId);
    _clientSecretCtrl = TextEditingController(text: linear.clientSecret);
  }

  @override
  void dispose() {
    _clientIdCtrl.dispose();
    _clientSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCredentials() async {
    await ref.read(linearProvider.notifier).setCredentials(
          _clientIdCtrl.text.trim(),
          _clientSecretCtrl.text.trim(),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credentials saved')),
      );
    }
  }

  Future<void> _connect() async {
    await _saveCredentials();
    if (!mounted) return;
    await ref.read(linearProvider.notifier).connect();
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect from Linear?'),
        content: const Text(
          'This will remove your Linear token and clear cached issues. '
          'Your Linear data will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(linearProvider.notifier).disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linear = ref.watch(linearProvider);
    final isConnected = linear.isConnected;
    final isConnecting = linear.status == LinearConnectionStatus.connecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linear Integration'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header Card ───────────────────────────────────────────
                _HeaderCard(theme: theme),
                const SizedBox(height: 16),

                // ── Setup Guide ──────────────────────────────────────────
                _SetupGuideCard(theme: theme),
                const SizedBox(height: 16),

                // ── Credentials Card ─────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.vpn_key,
                                color: theme.colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text('OAuth Credentials',
                                style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _clientIdCtrl,
                          enabled: !isConnected && !isConnecting,
                          decoration: const InputDecoration(
                            labelText: 'Client ID',
                            border: OutlineInputBorder(),
                            hintText: 'e.g. a1b2c3d4...',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _clientSecretCtrl,
                          enabled: !isConnected && !isConnecting,
                          obscureText: _secretObscured,
                          decoration: InputDecoration(
                            labelText: 'Client Secret',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_secretObscured
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(
                                  () => _secretObscured = !_secretObscured),
                            ),
                          ),
                        ),
                        if (!isConnected) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Redirect URI to register in Linear: '
                            'http://localhost:9874/callback',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(const ClipboardData(
                                  text: 'http://localhost:9874/callback'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Redirect URI copied')),
                              );
                            },
                            child: Text(
                              'Tap to copy redirect URI',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Connection Status Card ────────────────────────────────
                _ConnectionStatusCard(
                  linear: linear,
                  theme: theme,
                  onConnect: _connect,
                  onDisconnect: _disconnect,
                  onSync: () => ref.read(linearProvider.notifier).sync(),
                ),
                const SizedBox(height: 16),

                // ── Workspace Info Card (when connected) ─────────────────
                if (isConnected && linear.viewer != null) ...[
                  _WorkspaceCard(linear: linear, theme: theme),
                  const SizedBox(height: 16),
                ],

                // ── Stats Card (when connected) ───────────────────────────
                if (isConnected && linear.issues.isNotEmpty) ...[
                  _StatsCard(linear: linear, theme: theme),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final ThemeData theme;

  const _HeaderCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF5E6AD2).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.linear_scale,
                  color: Color(0xFF5E6AD2), size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Linear',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(
                    'Connect your Linear workspace to view and manage issues from AI VaultIO.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
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

class _SetupGuideCard extends StatelessWidget {
  final ThemeData theme;

  const _SetupGuideCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline,
                    color: theme.colorScheme.primary, size: 18),
                const SizedBox(width: 8),
                Text('Setup Guide',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _Step(
                n: 1,
                text:
                    'Go to Linear → Settings → API → OAuth Applications',
                theme: theme),
            _Step(n: 2, text: 'Click "Create new application"', theme: theme),
            _Step(
                n: 3,
                text: 'Set Redirect URI to: http://localhost:9874/callback',
                theme: theme),
            _Step(
                n: 4,
                text: 'Copy the Client ID and Client Secret here',
                theme: theme),
            _Step(n: 5, text: 'Click "Connect" below', theme: theme),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://linear.app/settings/api'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open Linear API Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  final ThemeData theme;

  const _Step({required this.n, required this.text, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$n',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  final LinearState linear;
  final ThemeData theme;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onSync;

  const _ConnectionStatusCard({
    required this.linear,
    required this.theme,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;

    switch (linear.status) {
      case LinearConnectionStatus.disconnected:
        statusColor = Colors.grey;
        statusIcon = Icons.link_off;
        statusLabel = 'Disconnected';
      case LinearConnectionStatus.connecting:
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        statusLabel = 'Connecting...';
      case LinearConnectionStatus.authenticated:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusLabel = 'Connected';
      case LinearConnectionStatus.syncing:
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        statusLabel = 'Syncing...';
      case LinearConnectionStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusLabel = 'Error';
    }

    final isConnected = linear.isConnected;
    final isConnecting =
        linear.status == LinearConnectionStatus.connecting ||
            linear.status == LinearConnectionStatus.syncing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.power, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Connection',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      isConnecting
                          ? SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: statusColor,
                              ),
                            )
                          : Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          )),
                    ],
                  ),
                ),
              ],
            ),
            if (linear.statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                linear.statusMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (linear.error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        linear.error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (!isConnected)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isConnecting ? null : onConnect,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Connect to Linear'),
                    ),
                  ),
                if (isConnected) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isConnecting ? null : onSync,
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Sync Now'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: isConnecting ? null : onDisconnect,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  final LinearState linear;
  final ThemeData theme;

  const _WorkspaceCard({required this.linear, required this.theme});

  @override
  Widget build(BuildContext context) {
    final viewer = linear.viewer!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.business,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Workspace',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(
                label: 'Organization',
                value: viewer.organizationName,
                theme: theme),
            _InfoRow(
                label: 'Signed in as',
                value: '${viewer.name} (${viewer.email})',
                theme: theme),
            if (linear.lastSyncAt != null)
              _InfoRow(
                label: 'Last synced',
                value: _formatDateTime(linear.lastSyncAt!),
                theme: theme,
              ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _InfoRow(
      {required this.label, required this.value, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final LinearState linear;
  final ThemeData theme;

  const _StatsCard({required this.linear, required this.theme});

  @override
  Widget build(BuildContext context) {
    final total = linear.issues.length;
    final active = linear.issues
        .where((i) => !i.state.isCompleted && !i.state.isCancelled)
        .length;
    final overdue = linear.issues.where((i) => i.isOverdue).length;
    final teamCount = linear.teamsFromIssues.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Sync Summary',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatChip(
                    label: 'Total', value: '$total', color: Colors.blue),
                _StatChip(
                    label: 'Active',
                    value: '$active',
                    color: Colors.green),
                _StatChip(
                    label: 'Overdue',
                    value: '$overdue',
                    color: overdue > 0 ? Colors.red : Colors.grey),
                _StatChip(
                    label: 'Teams',
                    value: '$teamCount',
                    color: Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
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
