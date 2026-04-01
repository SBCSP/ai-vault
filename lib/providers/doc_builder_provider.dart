import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart' as db;
import '../models/chat_session.dart';
import '../models/doc_block.dart';
import '../models/idea.dart';
import '../models/note.dart';
import '../services/ai_service.dart';
import '../services/docx_service.dart';
import '../services/embedding_service.dart';
import 'ai_provider.dart';
import 'embedding_provider.dart';
import 'ideas_provider.dart';
import 'notes_provider.dart';
import 'secrets_lock_provider.dart';
import 'vault_provider.dart';

// ─────────────────────────────────────────────────────────
// Document Builder State & Notifier
// ─────────────────────────────────────────────────────────

final docBuilderProvider =
    StateNotifierProvider<DocBuilderNotifier, DocBuilderState>((ref) {
  return DocBuilderNotifier();
});

class DocBuilderState {
  final String? filePath;
  final String? fileName;
  final List<DocBlock> blocks;
  final bool isDirty;
  final bool isLoading;
  final String? error;
  final int? selectedBlockIndex;

  /// Undo history — each entry is a snapshot of blocks.
  final List<List<DocBlock>> undoStack;
  final List<List<DocBlock>> redoStack;

  const DocBuilderState({
    this.filePath,
    this.fileName,
    this.blocks = const [],
    this.isDirty = false,
    this.isLoading = false,
    this.error,
    this.selectedBlockIndex,
    this.undoStack = const [],
    this.redoStack = const [],
  });

  bool get hasDocument => filePath != null;
  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  DocBuilderState copyWith({
    String? Function()? filePath,
    String? Function()? fileName,
    List<DocBlock>? blocks,
    bool? isDirty,
    bool? isLoading,
    String? Function()? error,
    int? Function()? selectedBlockIndex,
    List<List<DocBlock>>? undoStack,
    List<List<DocBlock>>? redoStack,
  }) {
    return DocBuilderState(
      filePath: filePath != null ? filePath() : this.filePath,
      fileName: fileName != null ? fileName() : this.fileName,
      blocks: blocks ?? this.blocks,
      isDirty: isDirty ?? this.isDirty,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      selectedBlockIndex: selectedBlockIndex != null
          ? selectedBlockIndex()
          : this.selectedBlockIndex,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
    );
  }
}

class DocBuilderNotifier extends StateNotifier<DocBuilderState> {
  DocBuilderNotifier() : super(const DocBuilderState());

  /// Push current blocks to undo stack before making a change.
  void _pushUndo() {
    final stack = [...state.undoStack, List<DocBlock>.from(state.blocks)];
    // Keep max 50 undo states
    if (stack.length > 50) stack.removeAt(0);
    state = state.copyWith(undoStack: stack, redoStack: []);
  }

  Future<void> loadDocument(String filePath) async {
    state = state.copyWith(
      isLoading: true,
      error: () => null,
    );

    try {
      final blocks = await DocxService.loadDocx(filePath);
      final name = filePath.split('/').last;
      state = DocBuilderState(
        filePath: filePath,
        fileName: name,
        blocks: blocks,
        isDirty: false,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: () => 'Failed to load document: $e',
      );
    }
  }

  Future<void> createNewDocument(String filePath) async {
    state = state.copyWith(isLoading: true, error: () => null);

    try {
      await DocxService.createNewDocx(filePath);
      final name = filePath.split('/').last;
      state = DocBuilderState(
        filePath: filePath,
        fileName: name,
        blocks: [
          const DocBlock(type: DocBlockType.heading1, content: 'Untitled Document'),
          const DocBlock(type: DocBlockType.paragraph, content: ''),
        ],
        isDirty: true,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: () => 'Failed to create document: $e',
      );
    }
  }

  Future<bool> saveDocument() async {
    if (state.filePath == null) return false;

    try {
      await DocxService.saveDocx(state.filePath!, state.blocks);
      state = state.copyWith(isDirty: false);
      return true;
    } catch (e) {
      state = state.copyWith(error: () => 'Failed to save: $e');
      return false;
    }
  }

  void closeDocument() {
    state = const DocBuilderState();
  }

  void selectBlock(int? index) {
    state = state.copyWith(selectedBlockIndex: () => index);
  }

  void updateBlock(int index, DocBlock block) {
    if (index < 0 || index >= state.blocks.length) return;
    _pushUndo();
    final updated = [...state.blocks];
    updated[index] = block;
    state = state.copyWith(blocks: updated, isDirty: true);
  }

  void deleteBlock(int index) {
    if (index < 0 || index >= state.blocks.length) return;
    _pushUndo();
    final updated = [...state.blocks]..removeAt(index);
    state = state.copyWith(
      blocks: updated,
      isDirty: true,
      selectedBlockIndex: () => null,
    );
  }

  /// Insert blocks after the given index. If index is null, append to end.
  void insertBlocksAt(int? afterIndex, List<DocBlock> newBlocks) {
    if (newBlocks.isEmpty) return;
    _pushUndo();
    final updated = [...state.blocks];
    final insertAt = afterIndex != null ? afterIndex + 1 : updated.length;
    updated.insertAll(insertAt.clamp(0, updated.length), newBlocks);
    state = state.copyWith(blocks: updated, isDirty: true);
  }

  /// Replace a block at the given index with new blocks.
  void replaceBlock(int index, List<DocBlock> newBlocks) {
    if (index < 0 || index >= state.blocks.length) return;
    _pushUndo();
    final updated = [...state.blocks];
    updated.removeAt(index);
    updated.insertAll(index, newBlocks);
    state = state.copyWith(blocks: updated, isDirty: true);
  }

  /// Apply an edit from the AI chat (replaces all blocks with undo support).
  void applyExternalEdit(List<DocBlock> newBlocks) {
    _pushUndo();
    state = state.copyWith(blocks: newBlocks, isDirty: true);
  }

  void addBlockAtEnd(DocBlock block) {
    _pushUndo();
    state = state.copyWith(
      blocks: [...state.blocks, block],
      isDirty: true,
    );
  }

  void undo() {
    if (!state.canUndo) return;
    final stack = [...state.undoStack];
    final previous = stack.removeLast();
    final redo = [...state.redoStack, List<DocBlock>.from(state.blocks)];
    state = state.copyWith(
      blocks: previous,
      undoStack: stack,
      redoStack: redo,
      isDirty: true,
    );
  }

  void redo() {
    if (!state.canRedo) return;
    final stack = [...state.redoStack];
    final next = stack.removeLast();
    final undo = [...state.undoStack, List<DocBlock>.from(state.blocks)];
    state = state.copyWith(
      blocks: next,
      undoStack: undo,
      redoStack: stack,
      isDirty: true,
    );
  }
}

// ─────────────────────────────────────────────────────────
// Document Builder Chat Notifier
// ─────────────────────────────────────────────────────────

final docBuilderChatProvider =
    StateNotifierProvider<DocBuilderChatNotifier, AiChatState>((ref) {
  return DocBuilderChatNotifier(ref);
});

class DocBuilderChatNotifier extends StateNotifier<AiChatState> {
  final Ref _ref;

  DocBuilderChatNotifier(this._ref) : super(const AiChatState());

  static const _systemPrompt = '''
You are a document editing assistant inside AI VaultIO. The user is working on a Word document (.docx).

IMPORTANT: You directly edit the document. When the user asks you to write, add, edit, replace, or delete content, you MUST include a ```doc_edits block with JSON edit commands. The edits are applied automatically to the document in real time.

EDIT COMMANDS FORMAT — wrap in a ```doc_edits fenced block:
```doc_edits
[
  {"op": "insert_after", "ref": 3, "content": "New paragraph text here"},
  {"op": "insert_before", "ref": 0, "content": "# New Title"},
  {"op": "replace", "ref": 5, "content": "Updated content for this block"},
  {"op": "delete", "ref": 7},
  {"op": "append", "content": "Content added to end of document"}
]
```

OPERATIONS:
- insert_after: Insert new content AFTER the block at index "ref"
- insert_before: Insert new content BEFORE the block at index "ref"
- replace: Replace the block at index "ref" with new content
- delete: Remove the block at index "ref"
- append: Add content to the end of the document (no "ref" needed)

RULES:
- "ref" is the block index number shown as [Block N] in the document
- "content" is plain text with structural markdown only: # headings, - bullet lists, 1. numbered lists
- Do NOT use inline markdown: no **bold**, *italic*, `code`, [links](url), or ~~strikethrough~~
- Multiple blocks in "content" are separated by blank lines
- You can include multiple operations in one edit block
- Always include conversational text OUTSIDE the edit block explaining what you did
- For questions, discussion, or when no document change is needed, just respond normally without an edit block
- Be smart about WHERE to place content. Read block indices carefully and insert at the logical location
- Match the tone and style of the existing document
''';

  Future<void> sendMessage(String query) async {
    if (query.trim().isEmpty) return;

    final userMessage = ChatMessage(text: query, isUser: true);
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isProcessing: true,
      error: () => null,
    );

    try {
      final aiService = _ref.read(aiServiceProvider);
      final llmProvider = _ref.read(llmProviderTypeProvider);
      final isCloud = llmProvider == LlmProviderType.claude;

      if (isCloud) {
        await _ref.read(secretsLockProvider.notifier).lock();
      }

      // Get document context
      final docState = _ref.read(docBuilderProvider);
      final docContext = docState.hasDocument
          ? DocxService.blocksToPlainText(docState.blocks)
          : 'No document loaded.';

      final selectedInfo = docState.selectedBlockIndex != null
          ? '\n\nSELECTED BLOCK: [Block ${docState.selectedBlockIndex}]'
          : '';

      // Build notes/ideas context for RAG
      final notesAsync = _ref.read(notesProvider);
      final notesList =
          notesAsync.whenOrNull<List<Note>>(data: (data) => data) ?? [];
      final ideasAsync = _ref.read(ideasProvider);
      final ideaList =
          ideasAsync.whenOrNull<List<Idea>>(data: (data) => data) ?? [];

      // RAG pipeline
      List<Note>? ragNotes;
      List<Idea>? ragIdeas;
      List<db.DocumentChunk>? ragChunks;
      List<String> ragDocumentTitles = [];
      List<ChatSession>? ragChatSessions;
      List<({String title, String content})>? ragWikiPages;
      bool ragUsed = false;

      try {
        final embeddingService = _ref.read(embeddingServiceProvider);
        final database = _ref.read(databaseProvider);
        final queryVector = await embeddingService.generateEmbedding(query);

        if (queryVector != null) {
          final allEmbeddings = await database.getAllEmbeddings();
          if (allEmbeddings.isNotEmpty) {
            final scored =
                <({String sourceId, String sourceType, double score})>[];
            for (final emb in allEmbeddings) {
              final vector = (jsonDecode(emb.embedding) as List<dynamic>)
                  .map((e) => (e as num).toDouble())
                  .toList();
              final score =
                  EmbeddingService.cosineSimilarity(queryVector, vector);
              scored.add((
                sourceId: emb.sourceId,
                sourceType: emb.sourceType,
                score: score,
              ));
            }
            scored.sort((a, b) => b.score.compareTo(a.score));
            final topK =
                scored.where((s) => s.score >= 0.3).take(5).toList();

            if (topK.isNotEmpty) {
              ragUsed = true;
              final noteIds = topK
                  .where((s) => s.sourceType == 'note')
                  .map((s) => s.sourceId)
                  .toSet();
              final ideaIds = topK
                  .where((s) => s.sourceType == 'idea')
                  .map((s) => s.sourceId)
                  .toSet();
              final chunkIds = topK
                  .where((s) => s.sourceType == 'document_chunk')
                  .map((s) => s.sourceId)
                  .toSet();

              ragNotes =
                  notesList.where((n) => noteIds.contains(n.id)).toList();
              ragIdeas =
                  ideaList.where((i) => ideaIds.contains(i.id)).toList();

              if (chunkIds.isNotEmpty) {
                ragChunks =
                    await database.getChunksByIds(chunkIds.toList());
                final docIds = ragChunks.map((c) => c.documentId).toSet();
                for (final docId in docIds) {
                  final doc = await database.getDocumentById(docId);
                  if (doc != null) ragDocumentTitles.add(doc.title);
                }
              }

              // Wiki pages
              final wikiIds = topK
                  .where((s) => s.sourceType == 'wiki_page')
                  .map((s) => s.sourceId)
                  .toSet();
              if (wikiIds.isNotEmpty) {
                ragWikiPages = [];
                for (final wikiId in wikiIds) {
                  final filePath = wikiId.replaceFirst('wiki:', '');
                  try {
                    final content =
                        await rootBundle.loadString('wiki/$filePath');
                    final titleMatch =
                        RegExp(r'^#\s+(.+)$', multiLine: true)
                            .firstMatch(content);
                    final title = titleMatch?.group(1) ?? filePath;
                    ragWikiPages.add((title: title, content: content));
                  } catch (_) {}
                }
              }
            }
          }
        }
      } catch (_) {
        // RAG failed — continue without it
      }

      // Build context
      final contextNotes = (ragNotes != null && ragNotes.isNotEmpty)
          ? ragNotes
          : notesList;
      final contextIdeas = (ragIdeas != null && ragIdeas.isNotEmpty)
          ? ragIdeas
          : ideaList;

      final vaultContext = aiService.buildVaultContext(
        [], // Don't include secrets in doc builder context
        contextNotes,
        ideas: contextIdeas,
        documentChunks: ragChunks,
        documentTitles: ragDocumentTitles,
        chatSessions: ragChatSessions,
        wikiPages: ragWikiPages,
      );

      final fullSystemPrompt =
          '$_systemPrompt\n\nCURRENT DOCUMENT:\n---\n$docContext$selectedInfo\n---\n\n$vaultContext';

      final history = state.messages.where((m) => m != userMessage).toList();

      if (isCloud) {
        // Claude streaming
        final claudeService = _ref.read(claudeApiProvider);

        final placeholder =
            ChatMessage(text: '', isUser: false, aiOnline: true, isCloudResponse: true);
        state = state.copyWith(
          messages: [...state.messages, placeholder],
        );

        final buffer = StringBuffer();
        await for (final chunk
            in claudeService.streamChat(query, history, fullSystemPrompt)) {
          if (!mounted) return;
          buffer.write(chunk);
          _updateLastMessage(buffer.toString());
        }

        if (!mounted) return;
        final fullText = aiService.cleanResponse(buffer.toString());

        // Parse and auto-apply edit commands
        final editResult = DocxService.parseEditCommands(fullText);
        String displayText = editResult.chatText;

        if (editResult.hasEdits) {
          displayText = _applyEdits(editResult, displayText);
        }

        _replaceLastMessage(ChatMessage(
          text: displayText,
          isUser: false,
          aiOnline: true,
          ragUsed: ragUsed,
          isCloudResponse: true,
        ));

        state = state.copyWith(isProcessing: false);
      } else {
        // Ollama streaming
        final aiStatus = await aiService.checkStatus();
        if (aiStatus.status != OllamaConnectionStatus.ready) {
          if (!mounted) return;
          state = state.copyWith(
            messages: [
              ...state.messages,
              ChatMessage(
                text:
                    "I'm currently offline. Connect Ollama to chat with me!",
                isUser: false,
                aiOnline: false,
              ),
            ],
            isProcessing: false,
          );
          return;
        }

        final messages = <Map<String, String>>[
          {'role': 'system', 'content': fullSystemPrompt},
          ...history.map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              }),
          {'role': 'user', 'content': query},
        ];

        final placeholder = ChatMessage(text: '', isUser: false, aiOnline: true);
        state = state.copyWith(
          messages: [...state.messages, placeholder],
        );

        final buffer = StringBuffer();
        await for (final chunk in aiService.streamChat(messages)) {
          if (!mounted) return;
          buffer.write(chunk);
          _updateLastMessage(buffer.toString());
        }

        if (!mounted) return;
        final fullText = aiService.cleanResponse(buffer.toString());

        // Parse and auto-apply edit commands
        final editResult = DocxService.parseEditCommands(fullText);
        String displayText = editResult.chatText;

        if (editResult.hasEdits) {
          displayText = _applyEdits(editResult, displayText);
        }

        _replaceLastMessage(ChatMessage(
          text: displayText,
          isUser: false,
          aiOnline: true,
          ragUsed: ragUsed,
        ));

        state = state.copyWith(isProcessing: false);
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isProcessing: false,
        error: () => e.toString(),
      );
    }
  }

  /// Apply edit commands to the document and return display text with summary.
  String _applyEdits(DocEditParseResult editResult, String chatText) {
    final docNotifier = _ref.read(docBuilderProvider.notifier);
    final docState = _ref.read(docBuilderProvider);

    final result = DocxService.applyEditCommands(
      docState.blocks,
      editResult.commands,
    );

    // Push undo and update blocks
    docNotifier.applyExternalEdit(result.blocks);

    // Build a summary to append to chat text
    final summaryBuf = StringBuffer();
    if (chatText.isNotEmpty) {
      summaryBuf.writeln(chatText);
      summaryBuf.writeln();
    }
    summaryBuf.writeln('---');
    summaryBuf.writeln('Document updated:');
    for (final line in result.summary) {
      summaryBuf.writeln('  \u2022 $line');
    }

    return summaryBuf.toString().trim();
  }

  void _updateLastMessage(String text) {
    final msgs = [...state.messages];
    if (msgs.isEmpty) return;
    final last = msgs.last;
    msgs[msgs.length - 1] = ChatMessage(
      text: text,
      isUser: last.isUser,
      aiOnline: last.aiOnline,
      isCloudResponse: last.isCloudResponse,
    );
    state = state.copyWith(messages: msgs);
  }

  void _replaceLastMessage(ChatMessage message) {
    final msgs = [...state.messages];
    if (msgs.isEmpty) return;
    msgs[msgs.length - 1] = message;
    state = state.copyWith(messages: msgs);
  }

  void newChat() {
    state = const AiChatState();
  }
}
