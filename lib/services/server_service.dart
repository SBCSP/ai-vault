import 'dart:convert';
import 'dart:io';

import 'agent_certificate_service.dart';

/// Metrics response types from aiv_agent.
class PerformanceMetrics {
  final String hostname;
  final double cpuPercent;
  final int memoryTotalBytes;
  final int memoryUsedBytes;
  final int memoryFreeBytes;
  final double memoryUsedPercent;
  final double loadAvg1;
  final double loadAvg5;
  final double loadAvg15;
  final double uptimeSeconds;
  final int numCPUs;

  PerformanceMetrics.fromJson(Map<String, dynamic> json)
      : hostname = json['hostname'] ?? '',
        cpuPercent = (json['cpu_percent'] ?? 0).toDouble(),
        memoryTotalBytes = json['memory_total_bytes'] ?? 0,
        memoryUsedBytes = json['memory_used_bytes'] ?? 0,
        memoryFreeBytes = json['memory_free_bytes'] ?? 0,
        memoryUsedPercent = (json['memory_used_percent'] ?? 0).toDouble(),
        loadAvg1 = (json['load_avg_1'] ?? 0).toDouble(),
        loadAvg5 = (json['load_avg_5'] ?? 0).toDouble(),
        loadAvg15 = (json['load_avg_15'] ?? 0).toDouble(),
        uptimeSeconds = (json['uptime_seconds'] ?? 0).toDouble(),
        numCPUs = json['num_cpus'] ?? 0;
}

class DiskMetrics {
  final List<FilesystemInfo> filesystems;

  DiskMetrics.fromJson(Map<String, dynamic> json)
      : filesystems = (json['filesystems'] as List? ?? [])
            .map((f) => FilesystemInfo.fromJson(f))
            .toList();
}

class FilesystemInfo {
  final String device;
  final String mountPoint;
  final String fsType;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final double usedPercent;

  FilesystemInfo.fromJson(Map<String, dynamic> json)
      : device = json['device'] ?? '',
        mountPoint = json['mount_point'] ?? '',
        fsType = json['fs_type'] ?? '',
        totalBytes = json['total_bytes'] ?? 0,
        usedBytes = json['used_bytes'] ?? 0,
        freeBytes = json['free_bytes'] ?? 0,
        usedPercent = (json['used_percent'] ?? 0).toDouble();
}

class NetworkMetrics {
  final List<NetworkInterfaceInfo> interfaces;
  final ConnectionSummary connections;

  NetworkMetrics.fromJson(Map<String, dynamic> json)
      : interfaces = (json['interfaces'] as List? ?? [])
            .map((i) => NetworkInterfaceInfo.fromJson(i))
            .toList(),
        connections = ConnectionSummary.fromJson(json['connections'] ?? {});
}

class NetworkInterfaceInfo {
  final String name;
  final String state;
  final int rxBytes;
  final int txBytes;
  final String ipv4;

  NetworkInterfaceInfo.fromJson(Map<String, dynamic> json)
      : name = json['name'] ?? '',
        state = json['state'] ?? '',
        rxBytes = json['rx_bytes'] ?? 0,
        txBytes = json['tx_bytes'] ?? 0,
        ipv4 = json['ipv4'] ?? '';
}

class ConnectionSummary {
  final int tcpEstablished;
  final int tcpListening;
  final int tcpTimeWait;
  final int udpListening;
  final int total;

  ConnectionSummary.fromJson(Map<String, dynamic> json)
      : tcpEstablished = json['tcp_established'] ?? 0,
        tcpListening = json['tcp_listening'] ?? 0,
        tcpTimeWait = json['tcp_time_wait'] ?? 0,
        udpListening = json['udp_listening'] ?? 0,
        total = json['total'] ?? 0;
}

class ProcessMetrics {
  final int totalProcesses;
  final int running;
  final int sleeping;
  final List<ProcessInfo> topByCPU;
  final List<ProcessInfo> topByMemory;

  ProcessMetrics.fromJson(Map<String, dynamic> json)
      : totalProcesses = json['total_processes'] ?? 0,
        running = json['running'] ?? 0,
        sleeping = json['sleeping'] ?? 0,
        topByCPU = (json['top_by_cpu'] as List? ?? [])
            .map((p) => ProcessInfo.fromJson(p))
            .toList(),
        topByMemory = (json['top_by_memory'] as List? ?? [])
            .map((p) => ProcessInfo.fromJson(p))
            .toList();
}

class ProcessInfo {
  final int pid;
  final String user;
  final double cpuPercent;
  final double memPercent;
  final int rssBytes;
  final String command;

  ProcessInfo.fromJson(Map<String, dynamic> json)
      : pid = json['pid'] ?? 0,
        user = json['user'] ?? '',
        cpuPercent = (json['cpu_percent'] ?? 0).toDouble(),
        memPercent = (json['mem_percent'] ?? 0).toDouble(),
        rssBytes = json['rss_bytes'] ?? 0,
        command = json['command'] ?? '';
}

class ServiceMetrics {
  final List<ServiceInfo> services;

  ServiceMetrics.fromJson(Map<String, dynamic> json)
      : services = (json['services'] as List? ?? [])
            .map((s) => ServiceInfo.fromJson(s))
            .toList();
}

class ServiceInfo {
  final String name;
  final String activeState;
  final String subState;
  final String description;

  ServiceInfo.fromJson(Map<String, dynamic> json)
      : name = json['name'] ?? '',
        activeState = json['active_state'] ?? '',
        subState = json['sub_state'] ?? '',
        description = json['description'] ?? '';
}

/// HTTP client for communicating with aiv_agent on remote servers.
/// Uses mTLS for authentication.
class ServerService {
  HttpClient? _httpClient;

  /// Creates an mTLS-configured HTTP client.
  Future<HttpClient> _getClient() async {
    if (_httpClient != null) return _httpClient!;

    final clientCert = await AgentCertificateService.readClientCertPem();
    final clientKey = await AgentCertificateService.readClientKeyPem();
    final caCert = await AgentCertificateService.readCaCertPem();

    if (clientCert == null || clientKey == null || caCert == null) {
      throw StateError('Agent certificates not generated. Generate certificates first.');
    }

    final securityContext = SecurityContext();
    securityContext.useCertificateChainBytes(utf8.encode(clientCert));
    securityContext.usePrivateKeyBytes(utf8.encode(clientKey));
    securityContext.setTrustedCertificatesBytes(utf8.encode(caCert));

    _httpClient = HttpClient(context: securityContext)
      ..connectionTimeout = const Duration(seconds: 10);

    return _httpClient!;
  }

  /// Resets the HTTP client (e.g. after regenerating certificates).
  void resetClient() {
    _httpClient?.close();
    _httpClient = null;
  }

  /// Makes a GET request to the agent and returns the parsed JSON.
  Future<Map<String, dynamic>> _get(String host, int port, String path) async {
    final client = await _getClient();
    final request = await client.getUrl(Uri.parse('https://$host:$port$path'));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw HttpException('Agent returned ${response.statusCode}: $body');
    }

    return json.decode(body) as Map<String, dynamic>;
  }

  /// Check if the agent is reachable.
  Future<bool> checkHealth(String host, int port) async {
    try {
      final data = await _get(host, port, '/health');
      return data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<PerformanceMetrics> getPerformance(String host, int port) async {
    final data = await _get(host, port, '/metrics/performance');
    return PerformanceMetrics.fromJson(data);
  }

  Future<DiskMetrics> getDisk(String host, int port) async {
    final data = await _get(host, port, '/metrics/disk');
    return DiskMetrics.fromJson(data);
  }

  Future<NetworkMetrics> getNetwork(String host, int port) async {
    final data = await _get(host, port, '/metrics/network');
    return NetworkMetrics.fromJson(data);
  }

  Future<ProcessMetrics> getProcesses(String host, int port) async {
    final data = await _get(host, port, '/metrics/processes');
    return ProcessMetrics.fromJson(data);
  }

  Future<ServiceMetrics> getServices(String host, int port) async {
    final data = await _get(host, port, '/metrics/services');
    return ServiceMetrics.fromJson(data);
  }
}
