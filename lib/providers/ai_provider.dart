import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import '../models/vault_entry.dart';
import '../services/ai_service.dart';
import 'notes_provider.dart';
import 'vault_provider.dart';

final aiServiceProvider =
    StateNotifierProvider<AiServiceNotifier, AiService>((ref) {
  return AiServiceNotifier();
});

class AiServiceNotifier extends StateNotifier<AiService> {
  AiServiceNotifier() : super(AiService()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('ai_server_url');
    final model = prefs.getString('ai_model');
    if (url != null) state.updateServerUrl(url);
    if (model != null) state.updateModel(model);
  }

  Future<void> updateServerUrl(String url) async {
    state.updateServerUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_server_url', url);
  }

  Future<void> updateModel(String model) async {
    state.updateModel(model);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_model', model);
  }
}

// --- AI Chat Provider ---
// Maintains conversation history in memory for multi-turn chat.

final aiChatProvider =
    StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  return AiChatNotifier(ref);
});

class AiChatState {
  final List<ChatMessage> messages;
  final bool isProcessing;
  final String? error;

  const AiChatState({
    this.messages = const [],
    this.isProcessing = false,
    this.error,
  });

  AiChatState copyWith({
    List<ChatMessage>? messages,
    bool? isProcessing,
    String? Function()? error,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error != null ? error() : this.error,
    );
  }
}

class AiChatNotifier extends StateNotifier<AiChatState> {
  final Ref _ref;

  AiChatNotifier(this._ref) : super(const AiChatState());

  Future<void> sendMessage(String query) async {
    if (query.trim().isEmpty) return;

    // Add user message
    final userMessage = ChatMessage(
      text: query,
      isUser: true,
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isProcessing: true,
      error: () => null,
    );

    try {
      final aiService = _ref.read(aiServiceProvider);

      final entriesAsync = _ref.read(vaultEntriesProvider);
      final entries = entriesAsync.whenOrNull<List<VaultEntry>>(
            data: (data) => data,
          ) ??
          [];

      final notesAsync = _ref.read(notesProvider);
      final notesList = notesAsync.whenOrNull<List<Note>>(
            data: (data) => data,
          ) ??
          [];

      // Pass conversation history (exclude the message we just added —
      // the chat() method receives the query separately)
      final history = state.messages
          .where((m) => m != userMessage)
          .toList();

      final response = await aiService.chat(
        query,
        history,
        entries,
        notesList,
      );

      if (!mounted) return;

      final assistantMessage = ChatMessage(
        text: response.text,
        isUser: false,
        matchedEntries: response.matchedEntries,
        matchedNotes: response.matchedNotes,
        aiOnline: response.aiOnline,
        isVaultResult: response.isVaultResult,
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMessage],
        isProcessing: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isProcessing: false,
        error: () => e.toString(),
      );
    }
  }

  void newChat() {
    state = const AiChatState();
  }
}

// --- Model Download Provider ---
// Persists download state across navigation so downloads continue in background.

final modelDownloadProvider =
    StateNotifierProvider<ModelDownloadNotifier, ModelDownloadState>((ref) {
  return ModelDownloadNotifier(ref);
});

class ModelDownloadState {
  final bool isDownloading;
  final String? modelName;
  final String status;
  final double? progress; // 0.0 - 1.0
  final String? error;
  final bool completed;

  const ModelDownloadState({
    this.isDownloading = false,
    this.modelName,
    this.status = '',
    this.progress,
    this.error,
    this.completed = false,
  });

  ModelDownloadState copyWith({
    bool? isDownloading,
    String? modelName,
    String? status,
    double? Function()? progress,
    String? Function()? error,
    bool? completed,
  }) {
    return ModelDownloadState(
      isDownloading: isDownloading ?? this.isDownloading,
      modelName: modelName ?? this.modelName,
      status: status ?? this.status,
      progress: progress != null ? progress() : this.progress,
      error: error != null ? error() : this.error,
      completed: completed ?? this.completed,
    );
  }
}

class ModelDownloadNotifier extends StateNotifier<ModelDownloadState> {
  final Ref _ref;

  ModelDownloadNotifier(this._ref) : super(const ModelDownloadState());

  Future<void> downloadModel(String modelName) async {
    if (state.isDownloading) return; // Prevent concurrent downloads

    state = ModelDownloadState(
      isDownloading: true,
      modelName: modelName,
      status: 'Starting download...',
    );

    final aiService = _ref.read(aiServiceProvider);

    try {
      await for (final update in aiService.pullModel(modelName)) {
        if (!mounted) return;

        final status = update['status'] as String? ?? '';

        if (update.containsKey('error')) {
          state = ModelDownloadState(
            isDownloading: false,
            modelName: modelName,
            status: '',
            error: update['error'] as String?,
          );
          return;
        }

        if (update.containsKey('completed') && update.containsKey('total')) {
          final completed = update['completed'] as int;
          final total = update['total'] as int;
          if (total > 0) {
            final pct = (completed / total * 100).toStringAsFixed(0);
            final mb = (completed / 1024 / 1024).toStringAsFixed(0);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(0);
            state = ModelDownloadState(
              isDownloading: true,
              modelName: modelName,
              status: '$status — ${mb}MB / ${totalMb}MB ($pct%)',
              progress: completed / total,
            );
          }
        } else {
          state = ModelDownloadState(
            isDownloading: true,
            modelName: modelName,
            status: status,
          );
        }
      }

      if (mounted) {
        state = ModelDownloadState(
          isDownloading: false,
          modelName: modelName,
          status: 'Done! $modelName is ready to use.',
          completed: true,
        );
      }
    } catch (e) {
      if (mounted) {
        state = ModelDownloadState(
          isDownloading: false,
          modelName: modelName,
          error: e.toString(),
        );
      }
    }
  }

  void clearCompleted() {
    if (!state.isDownloading) {
      state = const ModelDownloadState();
    }
  }
}
