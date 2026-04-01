import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/doc_block.dart';
import '../providers/ai_provider.dart';
import '../providers/doc_builder_provider.dart';
import '../services/ai_service.dart';
import '../widgets/markdown_response.dart';

/// AI-powered document builder with split-pane layout.
class DocBuilderScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const DocBuilderScreen({super.key, this.embedded = false});

  @override
  ConsumerState<DocBuilderScreen> createState() => _DocBuilderScreenState();
}

class _DocBuilderScreenState extends ConsumerState<DocBuilderScreen> {
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  final _chatFocusNode = FocusNode();
  double _splitRatio = 0.55;

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    ref.read(docBuilderChatProvider.notifier).sendMessage(text);
    _chatFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollChatToBottom());
  }

  void _scrollChatToBottom() {
    if (_chatScrollController.hasClients) {
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Open Word Document',
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (!path.toLowerCase().endsWith('.docx')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a .docx file'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      ref.read(docBuilderProvider.notifier).loadDocument(path);
      ref.read(docBuilderChatProvider.notifier).newChat();
    }
  }

  Future<void> _createNewDocument() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Create New Document',
      fileName: 'untitled.docx',
    );
    if (result != null) {
      final path = result.endsWith('.docx') ? result : '$result.docx';
      ref.read(docBuilderProvider.notifier).createNewDocument(path);
      ref.read(docBuilderChatProvider.notifier).newChat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final docState = ref.watch(docBuilderProvider);
    final theme = Theme.of(context);

    final body = widget.embedded
        ? _buildBody(docState, theme)
        : Scaffold(
            appBar: AppBar(title: const Text('Document Builder')),
            body: _buildBody(docState, theme),
          );
    return body;
  }

  Widget _buildBody(DocBuilderState docState, ThemeData theme) {
    if (docState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!docState.hasDocument) {
      return _buildLandingPage(theme);
    }

    return Column(
      children: [
        _buildToolbar(docState, theme),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final docWidth = constraints.maxWidth * _splitRatio;
              final chatWidth = constraints.maxWidth * (1 - _splitRatio);
              return Row(
                children: [
                  SizedBox(
                    width: docWidth,
                    child: _DocumentPanel(
                      blocks: docState.blocks,
                      selectedIndex: docState.selectedBlockIndex,
                      onSelectBlock: (i) =>
                          ref.read(docBuilderProvider.notifier).selectBlock(i),
                      onUpdateBlock: (i, b) =>
                          ref.read(docBuilderProvider.notifier).updateBlock(i, b),
                      onDeleteBlock: (i) =>
                          ref.read(docBuilderProvider.notifier).deleteBlock(i),
                      onAddBlock: (afterIndex) =>
                          ref.read(docBuilderProvider.notifier).insertBlocksAt(
                            afterIndex,
                            [const DocBlock(type: DocBlockType.paragraph, content: '')],
                          ),
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _splitRatio += details.delta.dx / context.size!.width;
                          _splitRatio = _splitRatio.clamp(0.3, 0.7);
                        });
                      },
                      child: Container(
                        width: 6,
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                        child: Center(
                          child: Container(
                            width: 2,
                            height: 40,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.outline.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: chatWidth - 6,
                    child: _ChatPanel(
                      controller: _chatController,
                      scrollController: _chatScrollController,
                      focusNode: _chatFocusNode,
                      onSend: _sendChat,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLandingPage(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_document,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Document Builder',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create and edit Word documents with AI assistance.\nChat with the AI to write, edit, and improve your document.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _openDocument,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open .docx'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _createNewDocument,
                  icon: const Icon(Icons.add),
                  label: const Text('Create New'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(DocBuilderState docState, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.description, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              docState.fileName ?? 'Document',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (docState.isDirty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Unsaved changes',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.orange,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.undo, size: 18),
            tooltip: 'Undo',
            onPressed: docState.canUndo
                ? () => ref.read(docBuilderProvider.notifier).undo()
                : null,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 18),
            tooltip: 'Redo',
            onPressed: docState.canRedo
                ? () => ref.read(docBuilderProvider.notifier).redo()
                : null,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () async {
              final saved =
                  await ref.read(docBuilderProvider.notifier).saveDocument();
              if (saved && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Document saved'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close document',
            onPressed: () => _confirmClose(docState),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(DocBuilderState docState) async {
    if (!docState.isDirty) {
      ref.read(docBuilderProvider.notifier).closeDocument();
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content:
            const Text('Save your changes before closing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text('Discard',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save & Close'),
          ),
        ],
      ),
    );

    if (result == 'save') {
      await ref.read(docBuilderProvider.notifier).saveDocument();
      if (mounted) ref.read(docBuilderProvider.notifier).closeDocument();
    } else if (result == 'discard') {
      ref.read(docBuilderProvider.notifier).closeDocument();
    }
  }

}

// ──────────────────────────────────────────────
// Document Content Panel (left pane)
// ──────────────────────────────────────────────

class _DocumentPanel extends StatelessWidget {
  final List<DocBlock> blocks;
  final int? selectedIndex;
  final ValueChanged<int?> onSelectBlock;
  final void Function(int, DocBlock) onUpdateBlock;
  final ValueChanged<int> onDeleteBlock;
  final ValueChanged<int?> onAddBlock;

  const _DocumentPanel({
    required this.blocks,
    required this.selectedIndex,
    required this.onSelectBlock,
    required this.onUpdateBlock,
    required this.onDeleteBlock,
    required this.onAddBlock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (blocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Empty document',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => onAddBlock(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add content'),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => onSelectBlock(null),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: blocks.length + 1, // +1 for trailing add button
        itemBuilder: (context, index) {
          if (index == blocks.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: IconButton(
                  icon: Icon(Icons.add_circle_outline,
                      color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                  tooltip: 'Add block',
                  onPressed: () => onAddBlock(blocks.length - 1),
                ),
              ),
            );
          }

          final block = blocks[index];
          final isSelected = selectedIndex == index;

          return GestureDetector(
            onTap: () => onSelectBlock(index),
            child: _DocBlockWidget(
              block: block,
              index: index,
              isSelected: isSelected,
              onUpdate: (b) => onUpdateBlock(index, b),
              onDelete: () => onDeleteBlock(index),
              onAddBelow: () => onAddBlock(index),
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Document Block Widget
// ──────────────────────────────────────────────

class _DocBlockWidget extends StatefulWidget {
  final DocBlock block;
  final int index;
  final bool isSelected;
  final ValueChanged<DocBlock> onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onAddBelow;

  const _DocBlockWidget({
    required this.block,
    required this.index,
    required this.isSelected,
    required this.onUpdate,
    required this.onDelete,
    required this.onAddBelow,
  });

  @override
  State<_DocBlockWidget> createState() => _DocBlockWidgetState();
}

class _DocBlockWidgetState extends State<_DocBlockWidget> {
  bool _editing = false;
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.block.content);
  }

  @override
  void didUpdateWidget(covariant _DocBlockWidget old) {
    super.didUpdateWidget(old);
    if (old.block.content != widget.block.content && !_editing) {
      _editController.text = widget.block.content;
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _finishEdit() {
    setState(() => _editing = false);
    widget.onUpdate(widget.block.copyWith(content: _editController.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: widget.isSelected
              ? theme.colorScheme.primary
              : Colors.transparent,
          width: widget.isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
        color: widget.isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onDoubleTap: () => setState(() => _editing = true),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Block type indicator
              if (widget.isSelected)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.block.typeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(height: 4),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        icon: Icon(Icons.more_vert,
                            size: 16, color: theme.colorScheme.primary),
                        onSelected: (action) {
                          if (action == 'delete') widget.onDelete();
                          if (action == 'add_below') widget.onAddBelow();
                          if (action == 'edit') {
                            setState(() => _editing = true);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(
                              value: 'add_below', child: Text('Add below')),
                          const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ],
                  ),
                ),
              Expanded(child: _editing ? _buildEditor() : _buildContent(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _editController,
          maxLines: null,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.all(8),
          ),
          onSubmitted: (_) => _finishEdit(),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: _finishEdit,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Done'),
            ),
            TextButton(
              onPressed: () {
                _editController.text = widget.block.content;
                setState(() => _editing = false);
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme) {
    final block = widget.block;

    switch (block.type) {
      case DocBlockType.heading1:
        return Text(
          block.content,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        );
      case DocBlockType.heading2:
        return Text(
          block.content,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        );
      case DocBlockType.heading3:
        return Text(
          block.content,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        );
      case DocBlockType.paragraph:
        if (block.content.trim().isEmpty) {
          return Text(
            'Empty paragraph (double-tap to edit)',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              fontStyle: FontStyle.italic,
            ),
          );
        }
        return Text(block.content, style: theme.textTheme.bodyMedium);
      case DocBlockType.bulletList:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: block.content.split('\n').map((item) {
            return Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('\u2022 '),
                  Expanded(
                      child: Text(item, style: theme.textTheme.bodyMedium)),
                ],
              ),
            );
          }).toList(),
        );
      case DocBlockType.numberedList:
        final items = block.content.split('\n');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items.asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e.key + 1}. '),
                  Expanded(
                      child:
                          Text(e.value, style: theme.textTheme.bodyMedium)),
                ],
              ),
            );
          }).toList(),
        );
      case DocBlockType.table:
        if (block.tableData == null || block.tableData!.isEmpty) {
          return Text(block.content, style: theme.textTheme.bodyMedium);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 40,
            columnSpacing: 16,
            columns: (block.tableData!.first)
                .map((h) => DataColumn(label: Text(h,
                    style: const TextStyle(fontWeight: FontWeight.bold))))
                .toList(),
            rows: block.tableData!.skip(1).map((row) {
              return DataRow(
                cells:
                    row.map((cell) => DataCell(Text(cell))).toList(),
              );
            }).toList(),
          ),
        );
      case DocBlockType.pageBreak:
        return Divider(
            thickness: 2, color: theme.colorScheme.outlineVariant);
    }
  }
}

// ──────────────────────────────────────────────
// Chat Panel (right pane)
// ──────────────────────────────────────────────

class _ChatPanel extends ConsumerWidget {
  final TextEditingController controller;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final VoidCallback onSend;

  const _ChatPanel({
    required this.controller,
    required this.scrollController,
    required this.focusNode,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(docBuilderChatProvider);
    final theme = Theme.of(context);
    final llmProvider = ref.watch(llmProviderTypeProvider);
    final providerLabel =
        llmProvider == LlmProviderType.claude ? 'Claude' : 'Ollama';

    ref.listen(docBuilderChatProvider, (prev, next) {
      if (prev != null && next.messages.length > prev.messages.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {
            scrollController.animateTo(
              scrollController.position.maxScrollExtent + 200,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    return Column(
      children: [
        // Chat header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Document Assistant',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  providerLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: chatState.messages.isEmpty
              ? _buildSuggestions(theme)
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: chatState.messages.length,
                  itemBuilder: (context, index) {
                    final msg = chatState.messages[index];
                    return _ChatBubble(message: msg);
                  },
                ),
        ),

        // Processing indicator
        if (chatState.isProcessing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Writing...',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

        // Input area
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      onSend();
                    }
                  },
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Tell the AI what to write or change...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: chatState.isProcessing ? null : onSend,
                icon: const Icon(Icons.send, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestions(ThemeData theme) {
    final suggestions = [
      'Write an introduction',
      'Create an outline',
      'Add a conclusion',
      'Expand the selected section',
      'Proofread and fix issues',
      'Add a summary paragraph',
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note,
                size: 48,
                color: theme.colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'Ask the AI to edit your document directly',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: suggestions.map((s) {
                return ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    controller.text = s;
                    onSend();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Chat Bubble with Insert Actions
// ──────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    // Check if this message contains an edit summary
    final hasEditSummary =
        !isUser && message.text.contains('Document updated:');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.4,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser
                  ? theme.colorScheme.primary
                  : hasEditSummary
                      ? theme.colorScheme.tertiaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: isUser
                ? Text(
                    message.text,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasEditSummary) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_note,
                                size: 16,
                                color: theme.colorScheme.onTertiaryContainer),
                            const SizedBox(width: 4),
                            Text(
                              'Auto-edited',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      MarkdownResponse(data: message.text),
                    ],
                  ),
          ),
          // Copy action for AI responses
          if (!isUser && message.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionChip(
                    icon: Icons.copy,
                    label: 'Copy',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied to clipboard'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
