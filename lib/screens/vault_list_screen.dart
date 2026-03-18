import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/aws_provider.dart';
import '../providers/embedding_provider.dart';
import '../providers/vault_provider.dart';
import '../widgets/vault_entry_tile.dart';
import 'aws_settings_screen.dart';
import 'entry_form_screen.dart';

class VaultListScreen extends ConsumerStatefulWidget {
  const VaultListScreen({super.key});

  @override
  ConsumerState<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends ConsumerState<VaultListScreen> {
  String _textFilter = '';
  final _searchController = TextEditingController();
  bool _fabOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(vaultEntriesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Secrets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Simple local search
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _textFilter = value),
                  decoration: InputDecoration(
                    hintText: 'Filter secrets...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _textFilter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _textFilter = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
              Expanded(
                child: entriesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (entries) {
                    var filtered = entries;

                    if (_textFilter.isNotEmpty) {
                      final q = _textFilter.toLowerCase();
                      filtered = filtered.where((e) {
                        return e.title.toLowerCase().contains(q) ||
                            e.username.toLowerCase().contains(q) ||
                            e.url.toLowerCase().contains(q) ||
                            e.category.toLowerCase().contains(q) ||
                            e.tags.toLowerCase().contains(q);
                      }).toList();
                    }

                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              entries.isEmpty
                                  ? Icons.lock_open
                                  : Icons.search_off,
                              size: 64,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              entries.isEmpty
                                  ? 'Your vault is empty\nTap + to add your first entry'
                                  : 'No matching entries',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        return VaultEntryTile(
                          entry: entry,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  EntryFormScreen(entry: entry),
                            ),
                          ),
                          onDelete: () {
                            ref
                                .read(vaultActionsProvider)
                                .deleteEntry(entry.id);
                            ref
                                .read(embeddingIndexProvider.notifier)
                                .removeEntry(entry.id);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
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

  Widget _buildSpeedDial(BuildContext context) {
    final theme = Theme.of(context);
    final aws = ref.watch(awsProvider);

    // Determine if AWS SSO is configured (has a start URL)
    final awsConfigured = aws.ssoStartUrl.isNotEmpty;
    final awsConnected =
        aws.status == AwsConnectionStatus.authenticated &&
            aws.selectedAccountId != null &&
            aws.selectedRoleName != null;
    final awsSyncing = aws.status == AwsConnectionStatus.syncing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabOpen) ...[
          // Add New Secret
          _SpeedDialItem(
            icon: Icons.add_circle_outline,
            label: 'New Secret',
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
          // AWS Sync — only show if AWS is configured
          if (awsConfigured) ...[
            const SizedBox(height: 12),
            _SpeedDialItem(
              icon: Icons.cloud_download,
              label: awsSyncing ? 'Syncing...' : 'Sync AWS-SM',
              iconColor: Colors.orange.shade700,
              onTap: awsSyncing
                  ? () {} // no-op while syncing
                  : () {
                      setState(() => _fabOpen = false);
                      _handleAwsSync(aws, awsConnected);
                    },
              theme: theme,
            ),
          ],
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

  /// Handle AWS sync: if connected → sync, if expired → prompt reconnect.
  Future<void> _handleAwsSync(
      AwsState aws, bool awsConnected) async {
    if (awsConnected) {
      // Directly sync
      _doAwsSync();
    } else {
      // SSO expired or not connected — prompt
      _showSsoExpiredDialog(aws);
    }
  }

  Future<void> _doAwsSync() async {
    final notifier = ref.read(awsProvider.notifier);

    // Show syncing snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text('Syncing secrets from AWS...'),
          ],
        ),
        duration: const Duration(seconds: 60),
      ),
    );

    final result = await notifier.syncSecrets();

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              result.error != null
                  ? Icons.warning_amber
                  : Icons.check_circle,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(result.summary)),
          ],
        ),
        backgroundColor: result.error != null
            ? Colors.red.shade700
            : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showSsoExpiredDialog(AwsState aws) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.cloud_off,
            color: Colors.orange.shade700,
            size: 32,
          ),
        ),
        title: const Text('AWS SSO Session Expired'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your AWS SSO session has expired or is not connected. '
              'You need to re-authenticate to sync secrets from AWS Secrets Manager.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (aws.ssoStartUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        aws.ssoStartUrl,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _connectAndSync();
            },
            icon: const Icon(Icons.login, size: 18),
            label: const Text('Connect via SSO'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
          ),
        ],
      ),
    );
  }

  /// Connect via SSO then auto-sync once authenticated.
  Future<void> _connectAndSync() async {
    final notifier = ref.read(awsProvider.notifier);

    // Show connecting snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text('Connecting to AWS SSO...'),
          ],
        ),
        duration: const Duration(seconds: 120),
      ),
    );

    await notifier.connect();

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final aws = ref.read(awsProvider);

    if (aws.status == AwsConnectionStatus.authenticated) {
      // Connected — check if account/role already selected, then sync
      if (aws.selectedAccountId != null &&
          aws.selectedRoleName != null) {
        _doAwsSync();
      } else {
        // Need to select account/role — send to settings
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Connected! Please select an account and role in AWS settings to sync.',
            ),
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AwsSettingsScreen()),
                );
              },
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } else if (aws.status == AwsConnectionStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child:
                      Text(aws.error ?? 'Failed to connect')),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }
}

/// Speed dial menu item
class _SpeedDialItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ThemeData theme;
  final Color? iconColor;

  const _SpeedDialItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.theme,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          backgroundColor: iconColor,
          child: Icon(icon,
              color: iconColor != null ? Colors.white : null),
        ),
      ],
    );
  }
}
