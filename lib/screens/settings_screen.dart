import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ai_provider.dart';
import '../providers/api_server_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/aws_provider.dart';
import '../providers/category_provider.dart';
import '../providers/lock_timeout_provider.dart';
import '../providers/mcp_provider.dart';
import '../services/claude_api_service.dart';
import 'audit_log_screen.dart';
import 'aws_settings_screen.dart';
import 'mcp_servers_screen.dart';
import 'ollama_screen.dart';
import 'server_management_screen.dart';
import 'wiki_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const SettingsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentModel = ref.watch(aiServiceProvider).model;
    final llmProvider = ref.watch(llmProviderTypeProvider);

    final body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // LLM Provider Selector
                _buildLlmProviderSelector(theme, ref, llmProvider),
                const SizedBox(height: 16),
                // Ollama / AI link card
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const OllamaScreen()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.smart_toy,
                              color: llmProvider == LlmProviderType.ollama
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ollama Models',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Active: $currentModel',
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: theme
                                        .colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (llmProvider == LlmProviderType.ollama)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Claude API card
                _ClaudeApiCard(),
                const SizedBox(height: 16),
                _buildMcpCard(theme, ref),
                const SizedBox(height: 16),
                _buildAwsCard(theme, ref),
                const SizedBox(height: 16),
                // Server Management card
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ServerManagementScreen()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.dns,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Server Management',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Manage remote servers with aiv_agent',
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: theme
                                        .colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Wiki card
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const WikiScreen()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.menu_book,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Wiki',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Documentation and guides',
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: theme
                                        .colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Audit Log link card
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AuditLogScreen()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.history,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Audit Log',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'View all activity and changes',
                                  style:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: theme
                                        .colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const _LockTimeoutCard(),
                const SizedBox(height: 16),
                _CategoriesCard(),
                const SizedBox(height: 16),
                const _VaultApiCard(),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.help_outline,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Quick Start',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'To use AI search, you need Ollama installed '
                          'and running with a model downloaded:',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            '# Install Ollama from https://ollama.com\n\n'
                            '# Pull and run a model:\n'
                            'ollama run gemma3:1b\n\n'
                            '# Or manage models directly from\n'
                            '# the Ollama Models page above.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
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
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildMcpCard(ThemeData theme, WidgetRef ref) {
    final mcpState = ref.watch(mcpProvider);
    final connectedCount = mcpState.connectedCount;
    final toolCount = mcpState.toolCount;

    String subtitle;
    if (mcpState.servers.isEmpty) {
      subtitle = 'Connect to external tools';
    } else {
      subtitle = '$connectedCount server${connectedCount == 1 ? '' : 's'} connected, '
          '$toolCount tool${toolCount == 1 ? '' : 's'} available';
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const McpServersScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.extension, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MCP Servers',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (connectedCount > 0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$toolCount tools',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLlmProviderSelector(ThemeData theme, WidgetRef ref, LlmProviderType current) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Active LLM Provider',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ProviderChoice(
                    icon: Icons.smart_toy,
                    label: 'Ollama',
                    subtitle: 'Local',
                    isSelected: current == LlmProviderType.ollama,
                    color: Colors.green,
                    onTap: () => ref.read(llmProviderTypeProvider.notifier).setProvider(LlmProviderType.ollama),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProviderChoice(
                    icon: Icons.cloud,
                    label: 'Claude',
                    subtitle: 'Cloud',
                    isSelected: current == LlmProviderType.claude,
                    color: Colors.blue,
                    onTap: () {
                      final claude = ref.read(claudeApiProvider);
                      if (!claude.isConfigured) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Add your Claude API key below first'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                        return;
                      }
                      ref.read(llmProviderTypeProvider.notifier).setProvider(LlmProviderType.claude);
                    },
                  ),
                ),
              ],
            ),
            if (current == LlmProviderType.claude) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.lock, size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Secrets auto-locked. Switch to Ollama for secrets access.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAwsCard(ThemeData theme, WidgetRef ref) {
    final aws = ref.watch(awsProvider);
    final isConnected =
        aws.status == AwsConnectionStatus.authenticated ||
            aws.status == AwsConnectionStatus.syncing;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AwsSettingsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.cloud_download,
                  color: Colors.orange.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AWS Secrets Manager',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      isConnected
                          ? 'Connected — ${aws.selectedAccountId ?? 'no account'}'
                          : 'Pull secrets from AWS via SSO',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isConnected
                            ? Colors.green.shade700
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 10, color: Colors.green),
                      SizedBox(width: 3),
                      Text(
                        'SSO',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClaudeApiCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ClaudeApiCard> createState() => _ClaudeApiCardState();
}

class _ClaudeApiCardState extends ConsumerState<_ClaudeApiCard> {
  final _apiKeyController = TextEditingController();
  bool _keyVisible = false;
  bool _testing = false;
  bool? _testResult;

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final claude = ref.read(claudeApiProvider);
    final result = await claude.testConnection();
    if (mounted) {
      setState(() {
        _testing = false;
        _testResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final claude = ref.watch(claudeApiProvider);
    final llmProvider = ref.watch(llmProviderTypeProvider);
    final isActive = llmProvider == LlmProviderType.claude;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud, color: isActive ? Colors.blue : theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Claude API',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud, size: 10, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'Cloud',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Connect to Anthropic\'s Claude models for more powerful AI responses. '
              'Secrets are automatically locked when using cloud models.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            // Security warning
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Secrets are auto-locked when Claude is active. Switch to Ollama for secrets access.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // API Key input
            Text('API Key', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _apiKeyController..text = claude.apiKey,
              obscureText: !_keyVisible,
              decoration: InputDecoration(
                hintText: 'sk-ant-...',
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_keyVisible ? Icons.visibility_off : Icons.visibility, size: 18),
                      onPressed: () => setState(() => _keyVisible = !_keyVisible),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.save, size: 18),
                      tooltip: 'Save API key',
                      onPressed: () {
                        ref.read(claudeApiProvider.notifier).updateApiKey(_apiKeyController.text.trim());
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('API key saved'), duration: Duration(seconds: 2)),
                        );
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Model selector
            Text('Model', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...ClaudeApiService.availableModels.map((entry) {
              final (modelId, name, desc) = entry;
              final isSelected = claude.model == modelId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: isSelected ? theme.colorScheme.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => ref.read(claudeApiProvider.notifier).updateModel(modelId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 18,
                            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Text(name, style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          )),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(desc, style: theme.textTheme.labelSmall?.copyWith(fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            // Test connection button
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: claude.isConfigured && !_testing ? _testConnection : null,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: Text(_testing ? 'Testing...' : 'Test Connection'),
                ),
                if (_testResult != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    _testResult! ? Icons.check_circle : Icons.error,
                    size: 18,
                    color: _testResult! ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _testResult! ? 'Connected' : 'Failed',
                    style: TextStyle(
                      color: _testResult! ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
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

class _LockTimeoutCard extends ConsumerWidget {
  const _LockTimeoutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentTimeout = ref.watch(lockTimeoutProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Vault Lock Timeout',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Automatically lock the vault after a period of inactivity.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ...LockTimeout.values.map((timeout) {
              final isSelected = currentTimeout == timeout;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: isSelected
                      ? theme.colorScheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => ref
                        .read(lockTimeoutProvider.notifier)
                        .setTimeout(timeout),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 20,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            timeout.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.15)
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              timeout.subtitle,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (timeout == LockTimeout.never) ...[
                            const Spacer(),
                            Icon(
                              Icons.warning_amber,
                              size: 16,
                              color: Colors.orange.shade700,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            if (currentTimeout == LockTimeout.never)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Auto-lock is disabled. Your vault will stay unlocked until you manually lock it.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange.shade700,
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
}

class _CategoriesCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoryProvider);
    final notifier = ref.read(categoryProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.category, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Categories',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showAddDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.map((cat) {
                final isDefault = notifier.isDefault(cat);
                return Chip(
                  label: Text(cat),
                  avatar: Icon(
                    isDefault ? Icons.lock_outline : Icons.label,
                    size: 16,
                  ),
                  deleteIcon: isDefault
                      ? null
                      : const Icon(Icons.close, size: 16),
                  onDeleted: isDefault
                      ? null
                      : () => _confirmDelete(context, ref, cat),
                  backgroundColor: isDefault
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.tertiaryContainer,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'Default categories cannot be removed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('New Category'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Category name',
              hintText: 'e.g. Database, Cloud, Certificate',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      await ref.read(categoryProvider.notifier).addCategory(result);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, String category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Category'),
        content: Text(
          'Remove "$category"? Existing entries with this category will keep it, but it won\'t appear in the dropdown anymore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(categoryProvider.notifier).removeCategory(category);
    }
  }
}

class _VaultApiCard extends ConsumerStatefulWidget {
  const _VaultApiCard();

  @override
  ConsumerState<_VaultApiCard> createState() => _VaultApiCardState();
}

class _VaultApiCardState extends ConsumerState<_VaultApiCard> {
  final _portController = TextEditingController();
  bool _keyVisible = false;

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  Future<void> _toggleEnabled(bool val) async {
    if (!val) {
      // Warn user the API key will be recycled
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Disable Vault API?'),
          content: const Text(
            'Disabling the Vault API will invalidate the current API key. '
            'A new key will be generated when re-enabled. Any applications '
            'using the current key will need to be updated.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Disable'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    ref.read(apiServerProvider.notifier).setEnabled(val);
    setState(() => _keyVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apiState = ref.watch(apiServerProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.api, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Vault API',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock, size: 10, color: Colors.white),
                          SizedBox(width: 3),
                          Text(
                            'HTTPS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: apiState.enabled,
                  onChanged: _toggleEnabled,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Expose a secure local REST API so other apps on this machine '
              'can access your vault programmatically. All traffic is '
              'encrypted with a self-signed TLS certificate.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            // TLS Certificate section (always visible)
            const SizedBox(height: 12),
            _buildCertificateSection(theme, apiState),

            if (apiState.enabled) ...[
              const SizedBox(height: 12),
              // Status indicator
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: apiState.isRunning ? Colors.green : Colors.red,
                      boxShadow: [
                        BoxShadow(
                          color: (apiState.isRunning
                                  ? Colors.green
                                  : Colors.red)
                              .withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    apiState.isRunning
                        ? 'Running on https://localhost:${apiState.port}'
                        : 'Stopped',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: apiState.isRunning ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
              if (apiState.error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    apiState.error!,
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // API Key section
              Text(
                'API Key',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _keyVisible
                            ? (apiState.apiKey ?? '')
                            : '\u2022' * 24,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: _keyVisible ? 0 : 2,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _keyVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                      ),
                      tooltip:
                          _keyVisible ? 'Hide API key' : 'Show API key',
                      onPressed: () =>
                          setState(() => _keyVisible = !_keyVisible),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copy API key',
                      onPressed: () {
                        if (apiState.apiKey != null) {
                          Clipboard.setData(
                            ClipboardData(text: apiState.apiKey!),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('API key copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Port configuration
              Row(
                children: [
                  Text('Port:', style: theme.textTheme.bodyMedium),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _portController
                        ..text = apiState.port.toString(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (val) {
                        final port = int.tryParse(val);
                        if (port != null && port > 0 && port <= 65535) {
                          ref
                              .read(apiServerProvider.notifier)
                              .setPort(port);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Endpoint docs
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  '# Base URL\n'
                  'https://localhost:${apiState.port}\n\n'
                  '# Auth: Bearer token or query param\n'
                  'Authorization: Bearer <api_key>\n'
                  '   — or —\n'
                  '?api_key=<api_key>\n\n'
                  'GET /api/health\n'
                  'GET /api/secrets\n'
                  'GET /api/secrets/:id\n'
                  'GET /api/secrets?title=github\n'
                  'GET /api/notes\n'
                  'GET /api/notes/:id\n\n'
                  '# Example (self-signed cert)\n'
                  'curl -k https://localhost:${apiState.port}/api/health \\\n'
                  '  -H "Authorization: Bearer <key>"',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'HTTPS only — localhost access. Use -k or --insecure '
                      'flag with curl for the self-signed certificate.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateSection(
      ThemeData theme, ApiServerState apiState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: apiState.certReady
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: apiState.certReady
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                apiState.certReady
                    ? Icons.verified_user
                    : Icons.warning_amber,
                size: 16,
                color: apiState.certReady ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                'TLS Certificate',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: apiState.certReady
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  apiState.certReady ? 'Valid' : 'Not Ready',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color:
                        apiState.certReady ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          if (apiState.certReady && apiState.certInfo.isNotEmpty) ...[
            const SizedBox(height: 6),
            if (apiState.certInfo['expires'] != null)
              Text(
                'Expires: ${apiState.certInfo['expires']}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (apiState.certInfo['fingerprint'] != null)
              Text(
                'SHA-1: ${apiState.certInfo['fingerprint']}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
          if (!apiState.certReady) ...[
            const SizedBox(height: 4),
            Text(
              'Certificate generation failed. Please restart the app.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.orange,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderChoice extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _ProviderChoice({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : theme.colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? color : theme.colorScheme.onSurfaceVariant, size: 28),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : null,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
