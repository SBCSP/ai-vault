import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../database/database.dart';
import '../providers/server_provider.dart';
import '../providers/version_provider.dart';
import '../services/agent_certificate_service.dart';
import 'server_dashboard_screen.dart';

class ServerManagementScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const ServerManagementScreen({super.key, this.embedded = false});

  @override
  ConsumerState<ServerManagementScreen> createState() =>
      _ServerManagementScreenState();
}

class _ServerManagementScreenState
    extends ConsumerState<ServerManagementScreen> {
  bool _generatingCerts = false;
  bool _downloadingRpm = false;
  bool _downloadingBinary = false;
  String? _downloadError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serversAsync = ref.watch(serversProvider);
    final certsExist = ref.watch(agentCertsExistProvider);

    final body = SingleChildScrollView(
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
      );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Server Management')),
      body: body,
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
    final version = ref.watch(appVersionProvider);

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
                Expanded(
                  child: Text(
                    'Download Agent',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('v$version',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      )),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Download the matching aiv_agent v$version to deploy on your Linux server. '
              'After downloading, copy the agent and your server certificates to the remote host.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_downloadError != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_downloadError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          )),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _downloadingRpm ? null : () => _downloadAgent('rpm'),
                  icon: _downloadingRpm
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download, size: 18),
                  label: Text(_downloadingRpm ? 'Downloading...' : '.rpm (Linux)'),
                ),
                OutlinedButton.icon(
                  onPressed: _downloadingBinary ? null : () => _downloadAgent('binary'),
                  icon: _downloadingBinary
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download, size: 18),
                  label: Text(_downloadingBinary ? 'Downloading...' : 'Standalone Binary'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _showInstallInstructions(),
              icon: const Icon(Icons.help_outline, size: 16),
              label: const Text('Install instructions'),
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

  /// Downloads the aiv_agent from the matching GitHub Release.
  Future<void> _downloadAgent(String type) async {
    final version = ref.read(appVersionProvider);
    final certsDir = await AgentCertificateService.certsDirectoryPath;

    // Determine download URL and filename
    final String url;
    final String filename;
    if (type == 'rpm') {
      // RPM filename from GitHub Release
      url = 'https://github.com/SBCSP/ai-vault/releases/download/v$version/aiv_agent-$version-1.x86_64.rpm';
      filename = 'aiv_agent-$version-1.x86_64.rpm';
      setState(() { _downloadingRpm = true; _downloadError = null; });
    } else {
      url = 'https://github.com/SBCSP/ai-vault/releases/download/v$version/aiv_agent-linux-amd64';
      filename = 'aiv_agent-linux-amd64';
      setState(() { _downloadingBinary = true; _downloadError = null; });
    }

    try {
      // Download to the agent_certs directory (user already knows this path)
      final downloadsDir = Directory('$certsDir/downloads');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      final filePath = '${downloadsDir.path}/$filename';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await File(filePath).writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Downloaded $filename'),
            action: SnackBarAction(
              label: 'Show path',
              onPressed: () => _showDownloadSuccessDialog(filePath, certsDir),
            ),
          ));
          _showDownloadSuccessDialog(filePath, certsDir);
        }
      } else if (response.statusCode == 404) {
        setState(() => _downloadError =
            'v$version release not found on GitHub. The release may still be building.');
      } else {
        setState(() => _downloadError =
            'Download failed (HTTP ${response.statusCode})');
      }
    } catch (e) {
      setState(() => _downloadError = 'Download failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _downloadingRpm = false;
          _downloadingBinary = false;
        });
      }
    }
  }

  void _showDownloadSuccessDialog(String filePath, String certsDir) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 24),
            const SizedBox(width: 8),
            const Text('Download Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Agent downloaded to:'),
            const SizedBox(height: 8),
            _copiablePath(ctx, filePath),
            const SizedBox(height: 12),
            const Text('Server certificates are at:'),
            const SizedBox(height: 8),
            _copiablePath(ctx, certsDir),
            const SizedBox(height: 16),
            const Text(
              'Next steps:\n\n'
              '1. Copy the agent + certs to your server:\n'
              '   scp <agent_file> user@server:\n'
              '   scp server.crt server.key ca.crt user@server:/etc/aiv_agent/\n\n'
              '2. Install the agent on the server\n\n'
              '3. Add the server in AI VaultIO to start monitoring',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showInstallInstructions();
            },
            child: const Text('Full instructions'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showAnsiblePlaybook(filePath, certsDir);
            },
            child: const Text('Ansible Playbook'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _copiablePath(BuildContext ctx, String path) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(path,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 14),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showInstallInstructions() {
    final version = ref.read(appVersionProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install Instructions'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RPM Install (RHEL/CentOS/Fedora/Amazon Linux)',
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _codeBlock(
                '# Copy files to your server\n'
                'scp aiv_agent-$version-1.x86_64.rpm user@server:\n'
                'scp server.crt server.key ca.crt user@server:/tmp/\n\n'
                '# On the server:\n'
                'sudo rpm -i aiv_agent-$version-1.x86_64.rpm\n'
                'sudo cp /tmp/{server.crt,server.key,ca.crt} /etc/aiv_agent/\n'
                'sudo chown aiv_agent:aiv_agent /etc/aiv_agent/*\n'
                'sudo chmod 600 /etc/aiv_agent/server.key\n'
                'sudo systemctl restart aiv_agent',
              ),
              const SizedBox(height: 16),
              Text(
                'Standalone Binary',
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _codeBlock(
                '# Copy to server\n'
                'scp aiv_agent-linux-amd64 user@server:\n'
                'scp server.crt server.key ca.crt user@server:/tmp/\n\n'
                '# On the server:\n'
                'sudo cp aiv_agent-linux-amd64 /usr/local/bin/aiv_agent\n'
                'sudo chmod +x /usr/local/bin/aiv_agent\n'
                'sudo mkdir -p /etc/aiv_agent\n'
                'sudo cp /tmp/{server.crt,server.key,ca.crt} /etc/aiv_agent/\n\n'
                '# Run the agent:\n'
                'sudo aiv_agent --port 9090',
              ),
              const SizedBox(height: 16),
              Text(
                'Verify',
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _codeBlock(
                '# Check agent status\n'
                'sudo systemctl status aiv_agent\n\n'
                '# View logs\n'
                'sudo journalctl -u aiv_agent -f',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showAnsiblePlaybook(String agentPath, String certsDir) {
    final version = ref.read(appVersionProvider);
    final isRpm = agentPath.endsWith('.rpm');
    final filename = agentPath.split('/').last;

    final playbook = '''---
# Ansible Playbook: Install aiv_agent v$version
# Usage: ansible-playbook -i inventory.ini install_aiv_agent.yml

- name: Install aiv_agent on remote servers
  hosts: all
  become: true
  vars:
    agent_version: "$version"
    certs_dir: /etc/aiv_agent
    agent_port: 9090

  tasks:
    - name: Create aiv_agent group
      group:
        name: aiv_agent
        state: present

    - name: Create aiv_agent user
      user:
        name: aiv_agent
        group: aiv_agent
        system: true
        shell: /usr/sbin/nologin
        create_home: false

    - name: Create certificate directory
      file:
        path: "{{ certs_dir }}"
        state: directory
        owner: aiv_agent
        group: aiv_agent
        mode: "0750"
${isRpm ? '''
    - name: Copy RPM package to server
      copy:
        src: "$agentPath"
        dest: "/tmp/$filename"

    - name: Install aiv_agent RPM
      yum:
        name: "/tmp/$filename"
        state: present
        disable_gpg_check: true

    - name: Clean up RPM
      file:
        path: "/tmp/$filename"
        state: absent
''' : '''
    - name: Copy agent binary to server
      copy:
        src: "$agentPath"
        dest: /usr/local/bin/aiv_agent
        owner: root
        group: root
        mode: "0755"

    - name: Create systemd service
      copy:
        dest: /etc/systemd/system/aiv_agent.service
        content: |
          [Unit]
          Description=AI VaultIO Agent
          After=network.target

          [Service]
          Type=simple
          User=aiv_agent
          Group=aiv_agent
          ExecStart=/usr/local/bin/aiv_agent --port {{ agent_port }}
          Restart=on-failure
          RestartSec=5

          [Install]
          WantedBy=multi-user.target

    - name: Reload systemd
      systemd:
        daemon_reload: true
'''}
    - name: Copy server certificate
      copy:
        src: "$certsDir/server.crt"
        dest: "{{ certs_dir }}/server.crt"
        owner: aiv_agent
        group: aiv_agent
        mode: "0644"

    - name: Copy server key
      copy:
        src: "$certsDir/server.key"
        dest: "{{ certs_dir }}/server.key"
        owner: aiv_agent
        group: aiv_agent
        mode: "0600"

    - name: Copy CA certificate
      copy:
        src: "$certsDir/ca.crt"
        dest: "{{ certs_dir }}/ca.crt"
        owner: aiv_agent
        group: aiv_agent
        mode: "0644"

    - name: Enable and start aiv_agent
      systemd:
        name: aiv_agent
        enabled: true
        state: restarted''';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.terminal, color: Colors.teal, size: 24),
            const SizedBox(width: 8),
            const Text('Ansible Playbook'),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Save this as install_aiv_agent.yml and run with:',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _codeBlock(
                  'ansible-playbook -i inventory.ini install_aiv_agent.yml',
                ),
                const SizedBox(height: 16),
                _codeBlock(playbook),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: playbook));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Playbook copied to clipboard')),
              );
            },
            child: const Text('Copy Playbook'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _codeBlock(String code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          SelectableText(code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.copy, size: 14),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
            ),
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
