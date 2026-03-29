import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../providers/server_provider.dart';
import '../services/server_service.dart';

class ServerDashboardScreen extends ConsumerStatefulWidget {
  final Server server;

  const ServerDashboardScreen({super.key, required this.server});

  @override
  ConsumerState<ServerDashboardScreen> createState() =>
      _ServerDashboardScreenState();
}

class _ServerDashboardScreenState extends ConsumerState<ServerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _refreshTimer;

  // Metric data
  PerformanceMetrics? _performance;
  DiskMetrics? _disk;
  NetworkMetrics? _network;
  ProcessMetrics? _processes;
  ServiceMetrics? _services;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    _fetchCurrentTab();

    // Auto-refresh every 10 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchCurrentTab(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _fetchCurrentTab();
    }
  }

  Future<void> _fetchCurrentTab() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final svc = ref.read(serverServiceProvider);
    final host = widget.server.host;
    final port = widget.server.port;

    try {
      switch (_tabController.index) {
        case 0:
          _performance = await svc.getPerformance(host, port);
        case 1:
          _disk = await svc.getDisk(host, port);
        case 2:
          _network = await svc.getNetwork(host, port);
        case 3:
          _processes = await svc.getProcesses(host, port);
        case 4:
          _services = await svc.getServices(host, port);
      }
    } catch (e) {
      _error = e.toString();
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.server.name),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.speed), text: 'Performance'),
            Tab(icon: Icon(Icons.storage), text: 'Disk'),
            Tab(icon: Icon(Icons.lan), text: 'Network'),
            Tab(icon: Icon(Icons.memory), text: 'Processes'),
            Tab(icon: Icon(Icons.miscellaneous_services), text: 'Services'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _fetchCurrentTab,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPerformanceTab(),
          _buildDiskTab(),
          _buildNetworkTab(),
          _buildProcessesTab(),
          _buildServicesTab(),
        ],
      ),
    );
  }

  Widget _wrapContent(Widget child) {
    if (_loading && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('Connection Error',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _fetchCurrentTab,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return child;
  }

  // ───── Performance Tab ─────

  Widget _buildPerformanceTab() {
    return _wrapContent(_performance == null
        ? const SizedBox.shrink()
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  children: [
                    _metricHeader('Hostname', _performance!.hostname),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: _gaugeCard(
                                'CPU', _performance!.cpuPercent, Colors.blue)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _gaugeCard('Memory',
                                _performance!.memoryUsedPercent, Colors.orange)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('System Info',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            _kvRow('CPUs', '${_performance!.numCPUs}'),
                            _kvRow('Memory Total',
                                _formatBytes(_performance!.memoryTotalBytes)),
                            _kvRow('Memory Used',
                                _formatBytes(_performance!.memoryUsedBytes)),
                            _kvRow('Memory Free',
                                _formatBytes(_performance!.memoryFreeBytes)),
                            _kvRow('Load Avg (1/5/15)',
                                '${_performance!.loadAvg1.toStringAsFixed(2)} / ${_performance!.loadAvg5.toStringAsFixed(2)} / ${_performance!.loadAvg15.toStringAsFixed(2)}'),
                            _kvRow(
                                'Uptime', _formatUptime(_performance!.uptimeSeconds)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ));
  }

  // ───── Disk Tab ─────

  Widget _buildDiskTab() {
    return _wrapContent(_disk == null
        ? const SizedBox.shrink()
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  children: _disk!.filesystems.map((fs) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.folder,
                                    size: 20,
                                    color:
                                        Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(fs.mountPoint,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                                Text('${fs.usedPercent.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: fs.usedPercent > 90
                                            ? Colors.red
                                            : fs.usedPercent > 75
                                                ? Colors.orange
                                                : Colors.green)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: fs.usedPercent / 100,
                                minHeight: 8,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                color: fs.usedPercent > 90
                                    ? Colors.red
                                    : fs.usedPercent > 75
                                        ? Colors.orange
                                        : Colors.green,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _kvRow('Device', fs.device),
                            _kvRow('Type', fs.fsType),
                            _kvRow('Total', _formatBytes(fs.totalBytes)),
                            _kvRow('Used', _formatBytes(fs.usedBytes)),
                            _kvRow('Free', _formatBytes(fs.freeBytes)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ));
  }

  // ───── Network Tab ─────

  Widget _buildNetworkTab() {
    return _wrapContent(_network == null
        ? const SizedBox.shrink()
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Connection summary
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Connections',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            _kvRow('TCP Established',
                                '${_network!.connections.tcpEstablished}'),
                            _kvRow('TCP Listening',
                                '${_network!.connections.tcpListening}'),
                            _kvRow('TCP TIME_WAIT',
                                '${_network!.connections.tcpTimeWait}'),
                            _kvRow('UDP Listening',
                                '${_network!.connections.udpListening}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Interfaces
                    ..._network!.interfaces.map((iface) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              iface.state == 'UP' ? Icons.wifi : Icons.wifi_off,
                              color: iface.state == 'UP'
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            title: Text(iface.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'IP: ${iface.ipv4.isEmpty ? "N/A" : iface.ipv4}\n'
                              'RX: ${_formatBytes(iface.rxBytes)}  TX: ${_formatBytes(iface.txBytes)}',
                            ),
                            isThreeLine: true,
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ));
  }

  // ───── Processes Tab ─────

  Widget _buildProcessesTab() {
    return _wrapContent(_processes == null
        ? const SizedBox.shrink()
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _statChip('Total', '${_processes!.totalProcesses}'),
                            _statChip('Running', '${_processes!.running}',
                                color: Colors.green),
                            _statChip('Sleeping', '${_processes!.sleeping}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Top by CPU',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 16,
                          columns: const [
                            DataColumn(label: Text('PID')),
                            DataColumn(label: Text('User')),
                            DataColumn(label: Text('CPU%')),
                            DataColumn(label: Text('MEM%')),
                            DataColumn(label: Text('RSS')),
                            DataColumn(label: Text('Command')),
                          ],
                          rows: _processes!.topByCPU
                              .take(10)
                              .map((p) => DataRow(cells: [
                                    DataCell(Text('${p.pid}')),
                                    DataCell(Text(p.user)),
                                    DataCell(Text(
                                        p.cpuPercent.toStringAsFixed(1))),
                                    DataCell(Text(
                                        p.memPercent.toStringAsFixed(1))),
                                    DataCell(Text(_formatBytes(p.rssBytes))),
                                    DataCell(SizedBox(
                                      width: 200,
                                      child: Text(p.command,
                                          overflow: TextOverflow.ellipsis),
                                    )),
                                  ]))
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Top by Memory',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 16,
                          columns: const [
                            DataColumn(label: Text('PID')),
                            DataColumn(label: Text('User')),
                            DataColumn(label: Text('CPU%')),
                            DataColumn(label: Text('MEM%')),
                            DataColumn(label: Text('RSS')),
                            DataColumn(label: Text('Command')),
                          ],
                          rows: _processes!.topByMemory
                              .take(10)
                              .map((p) => DataRow(cells: [
                                    DataCell(Text('${p.pid}')),
                                    DataCell(Text(p.user)),
                                    DataCell(Text(
                                        p.cpuPercent.toStringAsFixed(1))),
                                    DataCell(Text(
                                        p.memPercent.toStringAsFixed(1))),
                                    DataCell(Text(_formatBytes(p.rssBytes))),
                                    DataCell(SizedBox(
                                      width: 200,
                                      child: Text(p.command,
                                          overflow: TextOverflow.ellipsis),
                                    )),
                                  ]))
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ));
  }

  // ───── Services Tab ─────

  Widget _buildServicesTab() {
    return _wrapContent(_services == null
        ? const SizedBox.shrink()
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  children: _services!.services.map((svc) {
                    final isActive = svc.activeState == 'active';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          isActive
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: isActive ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        title: Text(svc.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        subtitle: Text(svc.description,
                            style: const TextStyle(fontSize: 11)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isActive ? Colors.green : Colors.red)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            svc.subState,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isActive ? Colors.green : Colors.red,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ));
  }

  // ───── Helpers ─────

  Widget _metricHeader(String label, String value) {
    return Row(
      children: [
        Icon(Icons.dns, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value),
      ],
    );
  }

  Widget _gaugeCard(String label, double percent, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: percent / 100,
                      strokeWidth: 8,
                      backgroundColor: color.withValues(alpha: 0.15),
                      color: percent > 90
                          ? Colors.red
                          : percent > 70
                              ? Colors.orange
                              : color,
                    ),
                  ),
                  Text('${percent.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: percent > 90
                            ? Colors.red
                            : percent > 70
                                ? Colors.orange
                                : color,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String key, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(key,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color)),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatUptime(double seconds) {
    final days = (seconds / 86400).floor();
    final hours = ((seconds % 86400) / 3600).floor();
    final mins = ((seconds % 3600) / 60).floor();
    if (days > 0) return '${days}d ${hours}h ${mins}m';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}
