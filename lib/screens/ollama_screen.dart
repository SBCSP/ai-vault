import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../providers/ai_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/embedding_provider.dart';
import '../services/ai_service.dart';

class OllamaScreen extends ConsumerStatefulWidget {
  const OllamaScreen({super.key});

  @override
  ConsumerState<OllamaScreen> createState() => _OllamaScreenState();
}

class _OllamaScreenState extends ConsumerState<OllamaScreen> {
  late final TextEditingController _urlController;
  final _downloadModelController = TextEditingController();
  OllamaStatus? _status;
  bool _checking = false;
  List<_OllamaModelInfo> _models = [];

  @override
  void initState() {
    super.initState();
    final aiService = ref.read(aiServiceProvider);
    _urlController = TextEditingController(text: aiService.serverUrl);
    _refreshAll();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _downloadModelController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() => _checking = true);
    final aiService = ref.read(aiServiceProvider);

    try {
      final status = await aiService.checkStatus();
      final models = await _fetchModelDetails(aiService.serverUrl);
      if (mounted) {
        setState(() {
          _status = status;
          _models = models;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = const OllamaStatus(
            status: OllamaConnectionStatus.ollamaNotRunning,
          );
          _models = [];
          _checking = false;
        });
      }
    }
  }

  Future<List<_OllamaModelInfo>> _fetchModelDetails(String serverUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final models = json['models'] as List<dynamic>? ?? [];

      return models.map((m) {
        final map = m as Map<String, dynamic>;
        final name = map['name'] as String? ?? '';
        final size = map['size'] as int? ?? 0;
        final modifiedAt = map['modified_at'] as String? ?? '';
        final details = map['details'] as Map<String, dynamic>? ?? {};
        final family = details['family'] as String? ?? '';
        final paramSize = details['parameter_size'] as String? ?? '';
        final quantLevel = details['quantization_level'] as String? ?? '';

        return _OllamaModelInfo(
          name: name,
          size: size,
          modifiedAt: modifiedAt,
          family: family,
          parameterSize: paramSize,
          quantizationLevel: quantLevel,
        );
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return [];
    }
  }

  void _startDownload() {
    final modelName = _downloadModelController.text.trim();
    if (modelName.isEmpty) return;

    ref.read(modelDownloadProvider.notifier).downloadModel(modelName);
    _downloadModelController.clear();
    setState(() {});
  }

  Future<void> _deleteModel(String modelName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text(
          'Are you sure you want to delete "$modelName"?\n\n'
          'You will need to download it again to use it.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final aiService = ref.read(aiServiceProvider);
    try {
      final response = await http.delete(
        Uri.parse('${aiService.serverUrl}/api/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': modelName}),
      );

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$modelName deleted successfully')),
          );
          _refreshAll();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete $modelName'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentModel = ref.watch(aiServiceProvider).model;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ollama Models'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _checking ? null : _refreshAll,
          ),
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
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Connection status banner
                _buildConnectionBanner(theme),
                const SizedBox(height: 16),

                // Server URL
                _buildServerUrlCard(theme),
                const SizedBox(height: 16),

                // Active model
                _buildActiveModelCard(theme, currentModel),
                const SizedBox(height: 16),

                // Embedding model
                _buildEmbeddingModelCard(theme),
                const SizedBox(height: 16),

                // Download new model
                _buildDownloadCard(theme),
                const SizedBox(height: 16),

                // Installed models list
                _buildInstalledModelsCard(theme, currentModel),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionBanner(ThemeData theme) {
    if (_checking) {
      return Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Checking Ollama connection...'),
            ],
          ),
        ),
      );
    }

    if (_status == null) return const SizedBox.shrink();

    final Color color;
    final IconData icon;
    final String text;
    final String subtitle;

    switch (_status!.status) {
      case OllamaConnectionStatus.ready:
        color = Colors.green;
        icon = Icons.check_circle;
        text = 'Ollama Connected';
        subtitle = '${_models.length} model${_models.length == 1 ? '' : 's'} installed';
      case OllamaConnectionStatus.ollamaNotRunning:
        color = theme.colorScheme.error;
        icon = Icons.error;
        text = 'Ollama Not Running';
        subtitle = 'Install or start Ollama to manage models';
      case OllamaConnectionStatus.modelNotFound:
        color = Colors.orange;
        icon = Icons.warning;
        text = 'Ollama Connected — Active Model Missing';
        subtitle = 'Select an installed model or download one';
    }

    return Card(
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
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
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerUrlCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Server Configuration',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Ollama Server URL',
                hintText: 'http://localhost:11434',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                ref.read(aiServiceProvider.notifier).updateServerUrl(value);
                setState(() {
                  _status = null;
                  _models = [];
                });
              },
              onSubmitted: (_) => _refreshAll(),
            ),
            const SizedBox(height: 8),
            Text(
              'Default: http://localhost:11434',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveModelCard(ThemeData theme, String currentModel) {
    final modelNames = _models.map((m) => m.name).toList();

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
                  'Active Model',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    currentModel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'This is the model AI Vault uses for search and conversation.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_checking)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (modelNames.isEmpty)
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Select Model',
                  prefixIcon: Icon(Icons.smart_toy),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  'No models available — connect to Ollama first',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: modelNames.any(
                  (m) => m.toLowerCase() == currentModel.toLowerCase(),
                )
                    ? modelNames.firstWhere(
                        (m) =>
                            m.toLowerCase() == currentModel.toLowerCase(),
                      )
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Select Model',
                  prefixIcon: Icon(Icons.smart_toy),
                  border: OutlineInputBorder(),
                ),
                hint: Text(currentModel),
                items: modelNames.map((model) {
                  final info =
                      _models.firstWhere((m) => m.name == model);
                  final isActive =
                      model.toLowerCase() == currentModel.toLowerCase();
                  return DropdownMenuItem<String>(
                    value: model,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$model  (${info.sizeLabel})',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isActive)
                          Icon(
                            Icons.check_circle,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(aiServiceProvider.notifier).updateModel(value);
                    _refreshAll();
                  }
                },
                isExpanded: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbeddingModelCard(ThemeData theme) {
    final embeddingModel = ref.watch(embeddingModelProvider);
    final indexState = ref.watch(embeddingIndexProvider);
    final modelNames = _models.map((m) => m.name).toList();

    // Check if embedding model is installed
    final isInstalled = modelNames.any(
      (m) => m.toLowerCase() == embeddingModel.toLowerCase() ||
          m.toLowerCase().startsWith(embeddingModel.toLowerCase().split(':').first),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Embedding Model',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isInstalled
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isInstalled
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    isInstalled ? 'Installed' : 'Not Installed',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isInstalled ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Used for RAG search — finds relevant vault items for AI queries.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            // Embedding model dropdown
            if (_checking)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (modelNames.isEmpty)
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Embedding Model',
                  prefixIcon: Icon(Icons.hub),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  embeddingModel,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: modelNames.any(
                  (m) => m.toLowerCase() == embeddingModel.toLowerCase(),
                )
                    ? modelNames.firstWhere(
                        (m) =>
                            m.toLowerCase() == embeddingModel.toLowerCase(),
                      )
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Embedding Model',
                  prefixIcon: Icon(Icons.hub),
                  border: OutlineInputBorder(),
                ),
                hint: Text(embeddingModel),
                items: modelNames.map((model) {
                  final isActive =
                      model.toLowerCase() == embeddingModel.toLowerCase();
                  final info =
                      _models.firstWhere((m) => m.name == model);
                  return DropdownMenuItem<String>(
                    value: model,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$model  (${info.sizeLabel})',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isActive)
                          Icon(
                            Icons.check_circle,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(embeddingModelProvider.notifier)
                        .updateModel(value);
                  }
                },
                isExpanded: true,
              ),

            const SizedBox(height: 12),

            // Quick download button if not installed
            if (!isInstalled && !ref.watch(modelDownloadProvider).isDownloading)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(modelDownloadProvider.notifier)
                        .downloadModel(embeddingModel);
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: Text('Download $embeddingModel'),
                ),
              ),

            // Index status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.inventory_2,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        indexState.isIndexing
                            ? 'Indexing: ${indexState.processedItems}/${indexState.totalItems}'
                            : '${indexState.indexedCount} items indexed',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      if (!indexState.isIndexing)
                        TextButton.icon(
                          onPressed: () => ref
                              .read(embeddingIndexProvider.notifier)
                              .reindexAll(),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Re-index All'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                  if (indexState.isIndexing) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: indexState.totalItems > 0
                            ? indexState.processedItems /
                                indexState.totalItems
                            : null,
                        minHeight: 6,
                      ),
                    ),
                  ],
                  if (indexState.error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      indexState.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadCard(ThemeData theme) {
    final downloadState = ref.watch(modelDownloadProvider);
    final isPulling = downloadState.isDownloading;
    final hasStatus = downloadState.status.isNotEmpty ||
        downloadState.error != null ||
        downloadState.completed;

    // Auto-refresh model list when download completes
    if (downloadState.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(modelDownloadProvider.notifier).clearCompleted();
        _refreshAll();
      });
    }

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
                  'Download New Model',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _downloadModelController,
                    enabled: !isPulling,
                    decoration: InputDecoration(
                      labelText: 'Model Name',
                      hintText: 'e.g. llama3.2:1b, mistral, phi3',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      helperText:
                          'Browse models at ollama.com/library',
                      helperMaxLines: 2,
                      suffixIcon:
                          _downloadModelController.text.isNotEmpty &&
                                  !isPulling
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () {
                                    _downloadModelController.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _startDownload(),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton.icon(
                    onPressed: isPulling ||
                            _downloadModelController.text.trim().isEmpty
                        ? null
                        : _startDownload,
                    icon: isPulling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                ),
              ],
            ),
            if (isPulling || hasStatus) ...[
              const SizedBox(height: 12),
              if (isPulling && downloadState.modelName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Downloading ${downloadState.modelName}...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (downloadState.progress != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: downloadState.progress,
                    minHeight: 8,
                  ),
                ),
              if (downloadState.progress == null && isPulling)
                const ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                  child: LinearProgressIndicator(minHeight: 8),
                ),
              if (downloadState.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Error: ${downloadState.error}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else if (downloadState.status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    downloadState.status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: downloadState.status.startsWith('Done')
                          ? Colors.green
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInstalledModelsCard(ThemeData theme, String currentModel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Installed Models',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_models.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_checking)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_models.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _status?.status ==
                                OllamaConnectionStatus.ollamaNotRunning
                            ? 'Ollama is not running.\nStart Ollama to see installed models.'
                            : 'No models installed.\nDownload one above to get started.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._models.map((model) {
                final isActive = model.name.toLowerCase() ==
                    currentModel.toLowerCase();
                return _ModelListTile(
                  model: model,
                  isActive: isActive,
                  onActivate: () {
                    ref
                        .read(aiServiceProvider.notifier)
                        .updateModel(model.name);
                    _refreshAll();
                  },
                  onDelete: () => _deleteModel(model.name),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _ModelListTile extends StatelessWidget {
  final _OllamaModelInfo model;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  const _ModelListTile({
    required this.model,
    required this.isActive,
    required this.onActivate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: isActive
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              )
            : null,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            isActive ? Icons.check : Icons.smart_toy,
            color: isActive
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                model.name,
                style: TextStyle(
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ACTIVE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              _InfoChip(
                icon: Icons.sd_storage,
                label: model.sizeLabel,
                theme: theme,
              ),
              if (model.parameterSize.isNotEmpty) ...[
                const SizedBox(width: 8),
                _InfoChip(
                  icon: Icons.memory,
                  label: model.parameterSize,
                  theme: theme,
                ),
              ],
              if (model.quantizationLevel.isNotEmpty) ...[
                const SizedBox(width: 8),
                _InfoChip(
                  icon: Icons.compress,
                  label: model.quantizationLevel,
                  theme: theme,
                ),
              ],
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isActive)
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Set as active model',
                onPressed: onActivate,
                visualDensity: VisualDensity.compact,
              ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              tooltip: 'Delete model',
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _OllamaModelInfo {
  final String name;
  final int size;
  final String modifiedAt;
  final String family;
  final String parameterSize;
  final String quantizationLevel;

  _OllamaModelInfo({
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.family,
    required this.parameterSize,
    required this.quantizationLevel,
  });

  String get sizeLabel {
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(0)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / 1024 / 1024).toStringAsFixed(0)} MB';
    } else {
      return '${(size / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
  }
}
