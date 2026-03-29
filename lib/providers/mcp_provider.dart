import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../services/mcp_service.dart';
import 'audit_provider.dart';
import 'vault_provider.dart';

enum McpConnectionStatus { disconnected, connecting, connected, error }

class McpState {
  final List<McpServer> servers;
  final Map<String, McpConnectionStatus> connectionStatuses;
  final Map<String, String> connectionErrors;
  final List<McpToolInfo> availableTools;
  final bool isConnecting;

  const McpState({
    this.servers = const [],
    this.connectionStatuses = const {},
    this.connectionErrors = const {},
    this.availableTools = const [],
    this.isConnecting = false,
  });

  McpState copyWith({
    List<McpServer>? servers,
    Map<String, McpConnectionStatus>? connectionStatuses,
    Map<String, String>? connectionErrors,
    List<McpToolInfo>? availableTools,
    bool? isConnecting,
  }) {
    return McpState(
      servers: servers ?? this.servers,
      connectionStatuses: connectionStatuses ?? this.connectionStatuses,
      connectionErrors: connectionErrors ?? this.connectionErrors,
      availableTools: availableTools ?? this.availableTools,
      isConnecting: isConnecting ?? this.isConnecting,
    );
  }

  int get connectedCount =>
      connectionStatuses.values.where((s) => s == McpConnectionStatus.connected).length;

  int get toolCount => availableTools.length;
}

final mcpProvider = StateNotifierProvider<McpNotifier, McpState>((ref) {
  return McpNotifier(ref);
});

class McpNotifier extends StateNotifier<McpState> {
  final Ref _ref;
  final McpService mcpService = McpService();

  McpNotifier(this._ref) : super(const McpState()) {
    _init();
  }

  Future<void> _init() async {
    final db = _ref.read(databaseProvider);
    final servers = await db.getAllMcpServers();
    state = state.copyWith(servers: servers);
    await connectAll();
  }

  Future<void> addServer(String name, String url, String authToken) async {
    final db = _ref.read(databaseProvider);
    final id = const Uuid().v4();
    final now = DateTime.now();

    await db.insertMcpServer(McpServersCompanion.insert(
      id: id,
      name: name,
      url: url,
      authToken: Value(authToken),
      createdAt: now,
      updatedAt: now,
    ));

    final servers = await db.getAllMcpServers();
    state = state.copyWith(servers: servers);

    _ref.read(auditLoggerProvider).log(
      action: AuditAction.mcpServerAdded,
      targetType: 'mcp_server',
      targetId: id,
      targetName: name,
      details: url,
    );

    // Auto-connect
    await _connectServer(id, name, url, authToken);
  }

  Future<void> removeServer(String serverId) async {
    final server = state.servers.where((s) => s.id == serverId).firstOrNull;
    await mcpService.disconnect(serverId);

    final db = _ref.read(databaseProvider);
    await db.deleteMcpServer(serverId);

    final servers = await db.getAllMcpServers();
    final statuses = Map<String, McpConnectionStatus>.from(state.connectionStatuses)
      ..remove(serverId);
    final errors = Map<String, String>.from(state.connectionErrors)
      ..remove(serverId);

    state = state.copyWith(
      servers: servers,
      connectionStatuses: statuses,
      connectionErrors: errors,
      availableTools: mcpService.allTools,
    );

    if (server != null) {
      _ref.read(auditLoggerProvider).log(
        action: AuditAction.mcpServerRemoved,
        targetType: 'mcp_server',
        targetId: serverId,
        targetName: server.name,
      );
    }
  }

  Future<void> toggleServer(String serverId, bool enabled) async {
    final db = _ref.read(databaseProvider);
    await db.updateMcpServer(McpServersCompanion(
      id: Value(serverId),
      enabled: Value(enabled),
      updatedAt: Value(DateTime.now()),
    ));

    final servers = await db.getAllMcpServers();
    state = state.copyWith(servers: servers);

    final server = servers.where((s) => s.id == serverId).firstOrNull;
    if (server == null) return;

    if (enabled) {
      await _connectServer(serverId, server.name, server.url, server.authToken);
    } else {
      await mcpService.disconnect(serverId);
      final statuses = Map<String, McpConnectionStatus>.from(state.connectionStatuses)
        ..[serverId] = McpConnectionStatus.disconnected;
      state = state.copyWith(
        connectionStatuses: statuses,
        availableTools: mcpService.allTools,
      );
    }
  }

  Future<void> connectAll() async {
    state = state.copyWith(isConnecting: true);

    for (final server in state.servers) {
      if (server.enabled) {
        await _connectServer(server.id, server.name, server.url, server.authToken);
      }
    }

    state = state.copyWith(isConnecting: false);
  }

  Future<void> _connectServer(
    String id,
    String name,
    String url,
    String authToken,
  ) async {
    final statuses = Map<String, McpConnectionStatus>.from(state.connectionStatuses)
      ..[id] = McpConnectionStatus.connecting;
    state = state.copyWith(connectionStatuses: statuses);

    try {
      await mcpService.connect(
        serverId: id,
        serverName: name,
        url: url,
        authToken: authToken,
      );

      final updatedStatuses =
          Map<String, McpConnectionStatus>.from(state.connectionStatuses)
            ..[id] = McpConnectionStatus.connected;
      final errors = Map<String, String>.from(state.connectionErrors)
        ..remove(id);
      state = state.copyWith(
        connectionStatuses: updatedStatuses,
        connectionErrors: errors,
        availableTools: mcpService.allTools,
      );

      _ref.read(auditLoggerProvider).log(
        action: AuditAction.mcpConnected,
        targetType: 'mcp_server',
        targetId: id,
        targetName: name,
        details: '${mcpService.getServerTools(id).length} tools available',
      );
    } catch (e) {
      final updatedStatuses =
          Map<String, McpConnectionStatus>.from(state.connectionStatuses)
            ..[id] = McpConnectionStatus.error;
      final errors = Map<String, String>.from(state.connectionErrors)
        ..[id] = e.toString();
      state = state.copyWith(
        connectionStatuses: updatedStatuses,
        connectionErrors: errors,
        availableTools: mcpService.allTools,
      );

      _ref.read(auditLoggerProvider).log(
        action: AuditAction.mcpConnectionFailed,
        targetType: 'mcp_server',
        targetId: id,
        targetName: name,
        details: e.toString(),
      );
    }
  }

  Future<void> testConnection(String url, String authToken) async {
    final testService = McpService();
    try {
      await testService.connect(
        serverId: 'test',
        serverName: 'Test',
        url: url,
        authToken: authToken,
      );
      await testService.disconnect('test');
    } finally {
      await testService.disconnectAll();
    }
  }

  Future<void> reconnectServer(String serverId) async {
    final server = state.servers.where((s) => s.id == serverId).firstOrNull;
    if (server == null) return;
    await _connectServer(server.id, server.name, server.url, server.authToken);
  }

  @override
  void dispose() {
    mcpService.disconnectAll();
    super.dispose();
  }
}
