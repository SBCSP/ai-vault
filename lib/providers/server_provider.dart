import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../services/agent_certificate_service.dart';
import '../services/server_service.dart';
import 'audit_provider.dart';
import 'vault_provider.dart';

/// Watches all registered servers.
final serversProvider = StreamProvider<List<Server>>((ref) {
  final db = ref.read(databaseProvider);
  return db.watchAllServers();
});

/// Singleton ServerService for HTTP calls.
final serverServiceProvider = Provider<ServerService>((ref) {
  return ServerService();
});

/// Whether agent certificates have been generated.
final agentCertsExistProvider = FutureProvider<bool>((ref) {
  return AgentCertificateService.certificatesExist();
});

/// Agent certificate metadata.
final agentCertInfoProvider = FutureProvider<Map<String, String>>((ref) {
  return AgentCertificateService.getCertificateInfo();
});

/// Actions for managing servers.
final serverActionsProvider = Provider<ServerActions>((ref) {
  return ServerActions(
    db: ref.read(databaseProvider),
    service: ref.read(serverServiceProvider),
    audit: ref.read(auditLoggerProvider),
  );
});

class ServerActions {
  final AppDatabase db;
  final ServerService service;
  final AuditLogger audit;

  ServerActions({
    required this.db,
    required this.service,
    required this.audit,
  });

  Future<void> addServer({
    required String name,
    required String host,
    int port = 9090,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    await db.insertServer(ServersCompanion.insert(
      id: id,
      name: name,
      host: host,
      port: Value(port),
      createdAt: now,
      updatedAt: now,
    ));

    await audit.log(
      action: 'server.added',
      targetType: 'server',
      targetId: id,
      targetName: name,
      details: '$host:$port',
    );
  }

  Future<void> removeServer(Server server) async {
    await db.deleteServer(server.id);
    await audit.log(
      action: 'server.removed',
      targetType: 'server',
      targetId: server.id,
      targetName: server.name,
    );
  }

  Future<void> updateServerStatus(Server server, String status) async {
    await db.updateServer(ServersCompanion(
      id: Value(server.id),
      status: Value(status),
      lastSeenAt: status == 'online' ? Value(DateTime.now()) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<bool> checkServerHealth(Server server) async {
    try {
      final healthy = await service.checkHealth(server.host, server.port);
      await updateServerStatus(server, healthy ? 'online' : 'offline');
      return healthy;
    } catch (_) {
      await updateServerStatus(server, 'offline');
      return false;
    }
  }
}
