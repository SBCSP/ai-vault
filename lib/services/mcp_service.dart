import 'package:mcp_dart/mcp_dart.dart';

/// Information about a single MCP tool aggregated from a connected server.
class McpToolInfo {
  final String serverId;
  final String serverName;
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const McpToolInfo({
    required this.serverId,
    required this.serverName,
    required this.name,
    required this.description,
    required this.inputSchema,
  });
}

/// Tracks the result of executing an MCP tool call.
class ToolCallInfo {
  final String toolName;
  final String serverName;
  final Map<String, dynamic> arguments;
  final String? result;
  final String? error;
  final Duration? duration;

  const ToolCallInfo({
    required this.toolName,
    required this.serverName,
    required this.arguments,
    this.result,
    this.error,
    this.duration,
  });

  bool get isError => error != null;
}

/// Manages MCP client connections and tool execution.
class McpService {
  final Map<String, McpClient> _clients = {};
  final Map<String, List<McpToolInfo>> _serverTools = {};

  /// Maps tool name → server ID for routing tool calls.
  final Map<String, String> toolToServerMap = {};

  /// Connect to an MCP server.
  Future<void> connect({
    required String serverId,
    required String serverName,
    required String url,
    String authToken = '',
  }) async {
    // Disconnect existing connection if any
    await disconnect(serverId);

    final client = McpClient(
      Implementation(name: 'AI VaultIO', version: '1.0.0'),
    );

    final StreamableHttpClientTransport transport;
    if (authToken.isNotEmpty) {
      transport = StreamableHttpClientTransport(
        Uri.parse(url),
        opts: StreamableHttpClientTransportOptions(
          authProvider: _BearerAuthProvider(authToken),
        ),
      );
    } else {
      transport = StreamableHttpClientTransport(Uri.parse(url));
    }

    await client.connect(transport);
    _clients[serverId] = client;

    // Fetch and cache tools
    await _refreshServerTools(serverId, serverName);
  }

  /// Disconnect from a specific server.
  Future<void> disconnect(String serverId) async {
    final client = _clients.remove(serverId);
    if (client != null) {
      try {
        await client.close();
      } catch (_) {
        // Ignore close errors
      }
    }
    // Remove tools for this server
    final tools = _serverTools.remove(serverId);
    if (tools != null) {
      for (final tool in tools) {
        toolToServerMap.remove(tool.name);
      }
    }
  }

  /// Disconnect from all servers.
  Future<void> disconnectAll() async {
    final serverIds = _clients.keys.toList();
    for (final id in serverIds) {
      await disconnect(id);
    }
  }

  /// Check if a server is connected.
  bool isConnected(String serverId) => _clients.containsKey(serverId);

  /// Refresh tools from a single connected server.
  Future<void> _refreshServerTools(String serverId, String serverName) async {
    final client = _clients[serverId];
    if (client == null) return;

    final result = await client.listTools();
    final tools = result.tools.map((t) {
      final schema = t.inputSchema;
      final schemaMap = schema?.toJson() ?? <String, dynamic>{};

      return McpToolInfo(
        serverId: serverId,
        serverName: serverName,
        name: t.name,
        description: t.description ?? '',
        inputSchema: schemaMap,
      );
    }).toList();

    _serverTools[serverId] = tools;

    // Update tool-to-server mapping
    for (final tool in tools) {
      toolToServerMap[tool.name] = serverId;
    }
  }

  /// Get all tools from all connected servers.
  List<McpToolInfo> get allTools {
    return _serverTools.values.expand((tools) => tools).toList();
  }

  /// Get tools for a specific server.
  List<McpToolInfo> getServerTools(String serverId) {
    return _serverTools[serverId] ?? [];
  }

  /// Convert MCP tools to Ollama's tool-calling format.
  List<Map<String, dynamic>> getOllamaToolsJson() {
    return allTools.map((t) => {
      'type': 'function',
      'function': {
        'name': t.name,
        'description': t.description,
        'parameters': t.inputSchema.isNotEmpty
            ? t.inputSchema
            : {'type': 'object', 'properties': {}},
      },
    }).toList();
  }

  /// Call a tool on the appropriate MCP server.
  Future<String> callTool(
    String serverId,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final client = _clients[serverId];
    if (client == null) {
      throw Exception('Server $serverId is not connected');
    }

    final result = await client.callTool(
      CallToolRequest(name: toolName, arguments: arguments),
    );

    if (result.isError == true) {
      final errorText = result.content
          .whereType<TextContent>()
          .map((c) => c.text)
          .join('\n');
      throw Exception(errorText.isNotEmpty ? errorText : 'Tool call failed');
    }

    // Extract text content from result
    return result.content
        .whereType<TextContent>()
        .map((c) => c.text)
        .join('\n');
  }
}

/// Simple bearer token auth provider for MCP transport.
class _BearerAuthProvider implements OAuthClientProvider {
  final String _token;

  _BearerAuthProvider(this._token);

  @override
  Future<OAuthTokens?> tokens() async {
    return OAuthTokens(accessToken: _token);
  }

  @override
  Future<void> redirectToAuthorization() async {}
}
