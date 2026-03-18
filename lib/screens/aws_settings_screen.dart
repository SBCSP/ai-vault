import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/aws_provider.dart';

class AwsSettingsScreen extends ConsumerStatefulWidget {
  const AwsSettingsScreen({super.key});

  @override
  ConsumerState<AwsSettingsScreen> createState() => _AwsSettingsScreenState();
}

class _AwsSettingsScreenState extends ConsumerState<AwsSettingsScreen> {
  final _ssoUrlController = TextEditingController();
  String _selectedRegion = 'us-east-1';

  @override
  void initState() {
    super.initState();
    final aws = ref.read(awsProvider);
    _ssoUrlController.text = aws.ssoStartUrl;
    _selectedRegion = aws.region;
  }

  @override
  void dispose() {
    _ssoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aws = ref.watch(awsProvider);
    final notifier = ref.read(awsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AWS Secrets Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                _buildHeaderCard(theme),
                const SizedBox(height: 16),

                // SSO Configuration
                _buildConfigCard(theme, aws, notifier),
                const SizedBox(height: 16),

                // Connection Status & Actions
                _buildConnectionCard(theme, aws, notifier),

                // Account/Role Selection (shown after authenticated)
                if (aws.status == AwsConnectionStatus.authenticated ||
                    aws.status == AwsConnectionStatus.syncing) ...[
                  const SizedBox(height: 16),
                  _buildAccountRoleCard(theme, aws, notifier),
                ],

                // Sync section
                if (aws.selectedRoleName != null) ...[
                  const SizedBox(height: 16),
                  _buildSyncCard(theme, aws, notifier),
                ],

                // Sync History
                if (aws.lastSyncAt != null) ...[
                  const SizedBox(height: 16),
                  _buildSyncHistoryCard(theme, aws),
                ],

                const SizedBox(height: 16),
                _buildInfoCard(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.cloud_download,
                color: Colors.orange,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AWS Secrets Manager Sync',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pull secrets from AWS into your local vault using '
                    'AWS IAM Identity Center (SSO) authentication.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard(
      ThemeData theme, AwsState aws, AwsNotifier notifier) {
    final isConnected =
        aws.status == AwsConnectionStatus.authenticated ||
            aws.status == AwsConnectionStatus.syncing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'SSO Configuration',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ssoUrlController,
              enabled: !isConnected,
              decoration: InputDecoration(
                labelText: 'SSO Start URL',
                hintText: 'https://your-org.awsapps.com/start',
                prefixIcon: const Icon(Icons.link),
                border: const OutlineInputBorder(),
                helperText: 'Your AWS IAM Identity Center start URL',
                helperMaxLines: 2,
                filled: isConnected,
                fillColor: isConnected
                    ? theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedRegion,
              decoration: InputDecoration(
                labelText: 'AWS Region',
                prefixIcon: const Icon(Icons.public),
                border: const OutlineInputBorder(),
                filled: isConnected,
                fillColor: isConnected
                    ? theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5)
                    : null,
              ),
              items: awsRegions
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: isConnected
                  ? null
                  : (v) {
                      if (v != null) setState(() => _selectedRegion = v);
                    },
            ),
            if (!isConnected) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    notifier.setSsoConfig(
                      _ssoUrlController.text.trim(),
                      _selectedRegion,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Configuration saved'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save Config'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard(
      ThemeData theme, AwsState aws, AwsNotifier notifier) {
    final isConnecting = aws.status == AwsConnectionStatus.connecting;
    final isConnected = aws.status == AwsConnectionStatus.authenticated ||
        aws.status == AwsConnectionStatus.syncing;
    final hasError = aws.status == AwsConnectionStatus.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnected
                      ? Icons.cloud_done
                      : isConnecting
                          ? Icons.cloud_sync
                          : Icons.cloud_off,
                  color: isConnected
                      ? Colors.green
                      : isConnecting
                          ? Colors.blue
                          : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Connection',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                _buildStatusChip(theme, aws),
              ],
            ),
            const SizedBox(height: 12),

            // Status message
            if (aws.statusMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (isConnecting) ...[
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        aws.statusMessage!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // User code display (during device auth)
            if (aws.userCode != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(Icons.open_in_browser,
                        color: Colors.blue.shade700, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      'Complete authentication in your browser',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your code:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        aws.userCode!,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Error message
            if (hasError && aws.error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline,
                        size: 18, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        aws.error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Connect / Disconnect button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isConnected) ...[
                  OutlinedButton.icon(
                    onPressed: () => notifier.disconnect(),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ] else if (!isConnecting) ...[
                  FilledButton.icon(
                    onPressed: aws.ssoStartUrl.isEmpty
                        ? null
                        : () => notifier.connect(),
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Connect via SSO'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme, AwsState aws) {
    Color chipColor;
    String label;

    switch (aws.status) {
      case AwsConnectionStatus.disconnected:
        chipColor = Colors.grey;
        label = 'Disconnected';
        break;
      case AwsConnectionStatus.connecting:
        chipColor = Colors.blue;
        label = 'Connecting';
        break;
      case AwsConnectionStatus.authenticated:
        chipColor = Colors.green;
        label = 'Connected';
        break;
      case AwsConnectionStatus.syncing:
        chipColor = Colors.orange;
        label = 'Syncing';
        break;
      case AwsConnectionStatus.error:
        chipColor = Colors.red;
        label = 'Error';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: chipColor,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRoleCard(
      ThemeData theme, AwsState aws, AwsNotifier notifier) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Account & Role',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Account selector
            if (aws.accounts.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: aws.selectedAccountId,
                decoration: const InputDecoration(
                  labelText: 'AWS Account',
                  prefixIcon: Icon(Icons.business),
                  border: OutlineInputBorder(),
                ),
                items: aws.accounts.map((a) {
                  return DropdownMenuItem(
                    value: a.accountId,
                    child: Text(
                      '${a.accountName} (${a.accountId})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) notifier.selectAccount(v);
                },
              ),

            // Role selector
            if (aws.roles.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: aws.selectedRoleName,
                decoration: const InputDecoration(
                  labelText: 'IAM Role',
                  prefixIcon: Icon(Icons.security),
                  border: OutlineInputBorder(),
                ),
                items: aws.roles.map((r) {
                  return DropdownMenuItem(
                    value: r.roleName,
                    child: Text(r.roleName),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) notifier.selectRole(v);
                },
              ),
            ],

            if (aws.accounts.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Loading accounts...',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncCard(
      ThemeData theme, AwsState aws, AwsNotifier notifier) {
    final isSyncing = aws.status == AwsConnectionStatus.syncing;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Colors.orange.shade700,
              width: 4,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sync, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Sync Secrets',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Pull all secrets from AWS Secrets Manager into your local vault. '
                'Existing synced entries will be updated. New secrets will be created '
                'with the "API Key" category and tagged with "aws-sync".',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              if (isSyncing && aws.statusMessage != null) ...[
                LinearProgressIndicator(
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text(
                  aws.statusMessage!,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
              ],

              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: isSyncing
                      ? null
                      : () async {
                          final result = await notifier.syncSecrets();
                          if (mounted) {
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
                                    Expanded(
                                      child: Text(result.summary),
                                    ),
                                  ],
                                ),
                                backgroundColor: result.error != null
                                    ? Colors.red.shade700
                                    : Colors.green.shade700,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          }
                        },
                  icon: isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_download, size: 18),
                  label: Text(isSyncing ? 'Syncing...' : 'Sync Now'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncHistoryCard(ThemeData theme, AwsState aws) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Last Sync',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (aws.lastSyncAt != null)
              Text(
                _formatDateTime(aws.lastSyncAt!),
                style: theme.textTheme.bodyMedium,
              ),
            if (aws.lastSyncResult != null) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: aws.lastSyncResult!.error != null
                      ? theme.colorScheme.errorContainer
                      : Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  aws.lastSyncResult!.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: aws.lastSyncResult!.error != null
                        ? theme.colorScheme.onErrorContainer
                        : Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'How It Works',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStep(theme, '1', 'Configure',
                'Enter your AWS IAM Identity Center (SSO) start URL and region.'),
            _buildStep(theme, '2', 'Authenticate',
                'Click "Connect via SSO" to open your browser and log in to your AWS account.'),
            _buildStep(theme, '3', 'Select',
                'Choose the AWS account and IAM role to use for accessing Secrets Manager.'),
            _buildStep(theme, '4', 'Sync',
                'Pull secrets from AWS into your local vault. This is a one-way pull — your local vault is never pushed to AWS.'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.security, size: 16, color: Colors.amber.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pull-only sync ensures your local vault acts as a read-only '
                      'mirror. Secrets are managed centrally in AWS and distributed '
                      'securely to developer machines.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(
      ThemeData theme, String number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hr ago';

    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
