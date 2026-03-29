import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../providers/server_provider.dart';
import '../services/agent_certificate_service.dart';
import 'server_dashboard_screen.dart';

class ServerManagementScreen extends ConsumerStatefulWidget {
  const ServerManagementScreen({super.key});

  @override
  ConsumerState<ServerManagementScreen> createState() =>
      _ServerManagementScreenState();
}

class _ServerManagementScreenState
    extends ConsumerState<ServerManagementScreen> {
  bool _generatingCerts = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serversAsync = ref.watch(serversProvider);
    final certsExist = ref.watch(agentCertsExistProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Management'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Certificate section
                _buildCertificateCard(theme, certsExist),
                const SizedBox(height: 16),

                // Download agent section
                certsExist.when(
                  data: (exists) => exists
                      ? _buildDownloadCard(theme)
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),

                // Server list
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Registered Servers',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    certsExist.when(
                      data: (exists) => exists
                          ? FilledButton.icon(
                              onPressed: () => _showAddServerDialog(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Server'),
                            )
                          : const SizedBox.shrink(),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                serversAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                  data: (servers) => servers.isEmpty
                      ? Card(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(Icons.dns_outlined,
                                    size: 48,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.4)),
                                const SizedBox(height: 12),
                                Text(
                                  'No servers registered',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Generate certificates, install aiv_agent on your server, then add it here.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: servers
                              .map((s) => _ServerTile(server: s))
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCertificateCard(
      ThemeData theme, AsyncValue<bool> certsExist) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'mTLS Certificates',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Certificates are used to securely authenticate between your AI VaultIO app and remote aiv_agent servers.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            certsExist.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e',
                  style: TextStyle(color: theme.colorScheme.error)),
              data: (exists) {
                if (exists) {
                  return _buildCertInfo(theme);
                }
                return FilledButton.icon(
                  onPressed: _generatingCerts ? null : _generateCertificates,
                  icon: _generatingCerts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock, size: 18),
                  label: Text(
                      _generatingCerts ? 'Generating...' : 'Generate Certificates'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCertInfo(ThemeData theme) {
    final certInfo = ref.watch(agentCertInfoProvider);
    return certInfo.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const Text('Could not read certificate info'),
      data: (info) {
        final generated = info['generated'] ?? 'Unknown';
        final expires = info['expires'] ?? 'Unknown';
        final fingerprint = info['ca_fingerprint'] ?? 'Unknown';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text('Certificates generated',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            _infoRow('Generated', _formatDate(generated)),
            _infoRow('Expires', _formatDate(expires)),
            _infoRow('CA Fingerprint', fingerprint.length > 30
                ? '${fingerprint.substring(0, 30)}...'
                : fingerprint),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _generatingCerts
                      ? null
                      : () => _regenerateCertificates(),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Regenerate'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Download Agent',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Download the aiv_agent installer to deploy on your Linux server. '
              'The .rpm package includes the server certificates for mTLS authentication.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _showCertsLocationDialog(),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('.rpm (Linux)'),
                ),
                OutlinedButton.icon(
                  onPressed: null, // Coming soon
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('.deb (Coming soon)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }

  Future<void> _generateCertificates() async {
    setState(() => _generatingCerts = true);
    final success = await AgentCertificateService.generateCertificates();
    setState(() => _generatingCerts = false);

    ref.invalidate(agentCertsExistProvider);
    ref.invalidate(agentCertInfoProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? 'Certificates generated successfully'
            : 'Failed to generate certificates'),
      ));
    }
  }

  Future<void> _regenerateCertificates() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate Certificates?'),
        content: const Text(
          'This will invalidate all existing agent connections. '
          'You will need to redeploy the agent on all servers with the new certificates.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Regenerate')),
        ],
      ),
    );

    if (confirmed == true) {
      await AgentCertificateService.deleteCertificates();
      ref.read(serverServiceProvider).resetClient();
      await _generateCertificates();
    }
  }

  Future<void> _showCertsLocationDialog() async {
    final certsDir = await AgentCertificateService.certsDirectoryPath;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agent Download'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The server certificates needed for the agent are located at:',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      certsDir,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: certsDir));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Path copied')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'To deploy to your Linux server:\n\n'
              '1. Build the agent RPM:\n'
              '   cd aiv_agent && make rpm\n\n'
              '2. Copy the .rpm and certs to your server:\n'
              '   scp build/rpm/RPMS/**/*.rpm user@server:\n'
              '   scp <certs_dir>/server.* <certs_dir>/ca.crt user@server:/etc/aiv_agent/\n\n'
              '3. Install on the server:\n'
              '   sudo rpm -i aiv_agent-*.rpm\n\n'
              '4. The agent will start automatically on port 9090.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddServerDialog() async {
    final nameController = TextEditingController();
    final hostController = TextEditingController();
    final portController = TextEditingController(text: '9090');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Server'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  hintText: 'e.g. Production Web Server',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: hostController,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: 'e.g. 192.168.1.100 or server.example.com',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Host is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '9090',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Port is required';
                  final port = int.tryParse(v);
                  if (port == null || port < 1 || port > 65535) {
                    return 'Invalid port';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      await ref.read(serverActionsProvider).addServer(
            name: nameController.text.trim(),
            host: hostController.text.trim(),
            port: int.parse(portController.text.trim()),
          );
    }

    nameController.dispose();
    hostController.dispose();
    portController.dispose();
  }
}

/// Individual server list tile.
class _ServerTile extends ConsumerWidget {
  final Server server;

  const _ServerTile({required this.server});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final Color statusColor;
    final IconData statusIcon;
    switch (server.status) {
      case 'online':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
      case 'offline':
        statusColor = Colors.red;
        statusIcon = Icons.error;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(Icons.dns, color: statusColor, size: 20),
        ),
        title: Text(server.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${server.host}:${server.port}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status indicator
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 12, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    server.status.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Refresh button
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Check status',
              onPressed: () async {
                final actions = ref.read(serverActionsProvider);
                await actions.checkServerHealth(server);
              },
            ),
            // Delete button
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 20, color: theme.colorScheme.error),
              tooltip: 'Remove server',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Remove Server?'),
                    content: Text(
                        'Remove "${server.name}" from your server list?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Remove')),
                    ],
                  ),
                );
                if (confirmed == true) {
                  ref.read(serverActionsProvider).removeServer(server);
                }
              },
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServerDashboardScreen(server: server),
            ),
          );
        },
      ),
    );
  }
}
