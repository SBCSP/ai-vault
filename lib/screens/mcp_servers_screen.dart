import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/mcp_provider.dart';
import '../services/mcp_service.dart';

class McpServersScreen extends ConsumerStatefulWidget {
  const McpServersScreen({super.key});

  @override
  ConsumerState<McpServersScreen> createState() => _McpServersScreenState();
}

class _McpServersScreenState extends ConsumerState<McpServersScreen> {
  @override
  Widget build(BuildContext context) {
    final mcpState = ref.watch(mcpProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Servers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(authStateProvider.notifier).lock(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddServerDialog(context),
        child: const Icon(Icons.add),
      ),
      body: mcpState.servers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.extension_off,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No MCP servers configured',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add an MCP server to enable tool calling in chat',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: mcpState.servers.length,
              itemBuilder: (context, index) {
                final server = mcpState.servers[index];
                final status = mcpState.connectionStatuses[server.id] ??
                    McpConnectionStatus.disconnected;
                final error = mcpState.connectionErrors[server.id];
                final tools = ref
                    .read(mcpProvider.notifier)
                    .mcpService
                    .getServerTools(server.id);

                return _ServerCard(
                  server: server,
                  status: status,
                  error: error,
                  tools: tools,
                  onToggle: (enabled) {
                    ref.read(mcpProvider.notifier).toggleServer(server.id, enabled);
                  },
                  onReconnect: () {
                    ref.read(mcpProvider.notifier).reconnectServer(server.id);
                  },
                  onDelete: () => _confirmDelete(context, server.id, server.name),
                );
              },
            ),
    );
  }

  void _showAddServerDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final tokenController = TextEditingController();
    bool isTesting = false;
    String? testError;
    bool testSuccess = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add MCP Server'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Server Name',
                    hintText: 'e.g., Linear, GitHub',
                    prefixIcon: Icon(Icons.label),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'e.g., https://mcp.linear.app/mcp',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Auth Token (optional)',
                    hintText: 'Bearer token for authentication',
                    prefixIcon: Icon(Icons.key),
                  ),
                ),
                const SizedBox(height: 16),
                if (testError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      testError!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (testSuccess)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Connection successful!',
                          style: TextStyle(color: Colors.green[700], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: isTesting
                      ? null
                      : () async {
                          if (urlController.text.trim().isEmpty) return;
                          setDialogState(() {
                            isTesting = true;
                            testError = null;
                            testSuccess = false;
                          });
                          try {
                            await ref.read(mcpProvider.notifier).testConnection(
                              urlController.text.trim(),
                              tokenController.text.trim(),
                            );
                            setDialogState(() {
                              isTesting = false;
                              testSuccess = true;
                            });
                          } catch (e) {
                            setDialogState(() {
                              isTesting = false;
                              testError = e.toString();
                            });
                          }
                        },
                  icon: isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cable, size: 16),
                  label: Text(isTesting ? 'Testing...' : 'Test Connection'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final url = urlController.text.trim();
                if (name.isEmpty || url.isEmpty) return;

                ref.read(mcpProvider.notifier).addServer(
                  name,
                  url,
                  tokenController.text.trim(),
                );
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String serverId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove MCP Server'),
        content: Text('Remove "$name"? This will disconnect and delete the server configuration.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(mcpProvider.notifier).removeServer(serverId);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _ServerCard extends StatefulWidget {
  final dynamic server;
  final McpConnectionStatus status;
  final String? error;
  final List<McpToolInfo> tools;
  final ValueChanged<bool> onToggle;
  final VoidCallback onReconnect;
  final VoidCallback onDelete;

  const _ServerCard({
    required this.server,
    required this.status,
    required this.error,
    required this.tools,
    required this.onToggle,
    required this.onReconnect,
    required this.onDelete,
  });

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _toolsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (widget.status) {
      McpConnectionStatus.connected => Colors.green,
      McpConnectionStatus.connecting => Colors.orange,
      McpConnectionStatus.error => Colors.red,
      McpConnectionStatus.disconnected => Colors.grey,
    };
    final statusText = switch (widget.status) {
      McpConnectionStatus.connected => 'Connected',
      McpConnectionStatus.connecting => 'Connecting...',
      McpConnectionStatus.error => 'Error',
      McpConnectionStatus.disconnected => 'Disabled',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.extension, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.server.name,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        widget.server.url,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: widget.server.enabled,
                  onChanged: widget.onToggle,
                ),
                if (widget.status == McpConnectionStatus.error)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Reconnect',
                    onPressed: widget.onReconnect,
                  ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                  tooltip: 'Remove',
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            if (widget.error != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.error!,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (widget.tools.isNotEmpty) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => setState(() => _toolsExpanded = !_toolsExpanded),
                child: Row(
                  children: [
                    Icon(
                      _toolsExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.tools.length} tool${widget.tools.length == 1 ? '' : 's'} available',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (_toolsExpanded) ...[
                const SizedBox(height: 4),
                ...widget.tools.map((tool) => Padding(
                      padding: const EdgeInsets.only(left: 20, top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.build, size: 12, color: Colors.deepPurple),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tool.name,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (tool.description.isNotEmpty)
                                  Text(
                                    tool.description,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
