import 'dart:convert';
import 'dart:io';

import 'package:docx_creator/docx_creator.dart';

import '../models/doc_block.dart';

// ─────────────────────────────────────────────────────────
// Document Edit Commands
// ─────────────────────────────────────────────────────────

enum DocEditOp { insertAfter, insertBefore, replace, delete, append }

class DocEditCommand {
  final DocEditOp op;

  /// Block index reference (not required for append).
  final int? ref;

  /// Markdown content (not required for delete).
  final String? content;

  const DocEditCommand({required this.op, this.ref, this.content});

  @override
  String toString() => 'DocEditCommand($op, ref=$ref, content=${content?.substring(0, (content!.length).clamp(0, 40))}...)';
}

/// Result of parsing an LLM response that may contain edit commands.
class DocEditParseResult {
  /// The conversational text (edit blocks stripped out).
  final String chatText;

  /// Parsed edit commands, empty if none found.
  final List<DocEditCommand> commands;

  const DocEditParseResult({required this.chatText, required this.commands});

  bool get hasEdits => commands.isNotEmpty;
}

class DocxService {
  /// Load a .docx file and convert its content to a list of DocBlocks.
  static Future<List<DocBlock>> loadDocx(String filePath) async {
    final doc = await DocxReader.load(filePath);
    return _elementsToBlocks(doc.elements);
  }

  /// Save a list of DocBlocks to a .docx file.
  static Future<void> saveDocx(String filePath, List<DocBlock> blocks) async {
    final builder = DocxDocumentBuilder();

    for (final block in blocks) {
      switch (block.type) {
        case DocBlockType.heading1:
          builder.h1(block.content);
        case DocBlockType.heading2:
          builder.h2(block.content);
        case DocBlockType.heading3:
          builder.h3(block.content);
        case DocBlockType.paragraph:
          builder.p(block.content);
        case DocBlockType.bulletList:
          builder.bullet(block.content.split('\n'));
        case DocBlockType.numberedList:
          builder.numbered(block.content.split('\n'));
        case DocBlockType.table:
          if (block.tableData != null && block.tableData!.isNotEmpty) {
            builder.table(block.tableData!);
          }
        case DocBlockType.pageBreak:
          builder.pageBreak();
      }
    }

    final doc = builder.build();
    await DocxExporter().exportToFile(doc, filePath);
  }

  /// Create a new empty .docx file at the given path.
  static Future<void> createNewDocx(String filePath) async {
    final doc = DocxDocumentBuilder().p('').build();
    await DocxExporter().exportToFile(doc, filePath);
  }

  /// Check if a file exists.
  static Future<bool> fileExists(String filePath) async {
    return File(filePath).exists();
  }

  /// Convert a list of DocBlocks to plain text (for LLM context).
  static String blocksToPlainText(List<DocBlock> blocks) {
    return blocks
        .asMap()
        .entries
        .map((e) => '[Block ${e.key}] ${e.value.toPlainText()}')
        .join('\n\n');
  }

  /// Strip inline markdown formatting (bold, italic, code, links).
  static String _stripInlineMarkdown(String text) {
    var result = text;
    // Bold+italic: ***text*** or ___text___
    result = result.replaceAllMapped(
        RegExp(r'\*{3}(.+?)\*{3}|_{3}(.+?)_{3}'),
        (m) => m.group(1) ?? m.group(2) ?? '');
    // Bold: **text** or __text__
    result = result.replaceAllMapped(
        RegExp(r'\*{2}(.+?)\*{2}|_{2}(.+?)_{2}'),
        (m) => m.group(1) ?? m.group(2) ?? '');
    // Italic: *text* or _text_
    result = result.replaceAllMapped(
        RegExp(r'\*(.+?)\*|_(.+?)_'),
        (m) => m.group(1) ?? m.group(2) ?? '');
    // Inline code: `text`
    result = result.replaceAllMapped(RegExp(r'`(.+?)`'), (m) => m.group(1)!);
    // Links: [text](url)
    result =
        result.replaceAllMapped(RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1)!);
    // Strikethrough: ~~text~~
    result =
        result.replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m.group(1)!);
    return result;
  }

  /// Parse markdown text (from LLM output) into DocBlocks.
  static List<DocBlock> parseMarkdownToBlocks(String markdown) {
    final blocks = <DocBlock>[];
    final lines = markdown.split('\n');
    final buffer = StringBuffer();
    DocBlockType? currentListType;

    void flushBuffer() {
      if (buffer.isNotEmpty) {
        if (currentListType != null) {
          blocks.add(DocBlock(
            type: currentListType!,
            content: _stripInlineMarkdown(buffer.toString().trimRight()),
          ));
          currentListType = null;
        } else {
          blocks.add(DocBlock(
            type: DocBlockType.paragraph,
            content: _stripInlineMarkdown(buffer.toString().trim()),
          ));
        }
        buffer.clear();
      }
    }

    for (final line in lines) {
      final trimmed = line.trim();

      // Headings
      if (trimmed.startsWith('### ')) {
        flushBuffer();
        blocks.add(DocBlock(
          type: DocBlockType.heading3,
          content: _stripInlineMarkdown(trimmed.substring(4)),
        ));
        continue;
      }
      if (trimmed.startsWith('## ')) {
        flushBuffer();
        blocks.add(DocBlock(
          type: DocBlockType.heading2,
          content: _stripInlineMarkdown(trimmed.substring(3)),
        ));
        continue;
      }
      if (trimmed.startsWith('# ')) {
        flushBuffer();
        blocks.add(DocBlock(
          type: DocBlockType.heading1,
          content: _stripInlineMarkdown(trimmed.substring(2)),
        ));
        continue;
      }

      // Horizontal rule / page break
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        flushBuffer();
        blocks.add(const DocBlock(
          type: DocBlockType.pageBreak,
          content: '',
        ));
        continue;
      }

      // Bullet list items
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        if (currentListType != DocBlockType.bulletList) {
          flushBuffer();
          currentListType = DocBlockType.bulletList;
        } else if (buffer.isNotEmpty) {
          buffer.write('\n');
        }
        buffer.write(trimmed.substring(2));
        continue;
      }

      // Numbered list items
      final numberedMatch = RegExp(r'^\d+\.\s').firstMatch(trimmed);
      if (numberedMatch != null) {
        if (currentListType != DocBlockType.numberedList) {
          flushBuffer();
          currentListType = DocBlockType.numberedList;
        } else if (buffer.isNotEmpty) {
          buffer.write('\n');
        }
        buffer.write(trimmed.substring(numberedMatch.end));
        continue;
      }

      // Empty line — flush
      if (trimmed.isEmpty) {
        flushBuffer();
        continue;
      }

      // Plain text — accumulate into paragraph
      if (currentListType != null) {
        flushBuffer();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(trimmed);
    }

    flushBuffer();
    return blocks;
  }

  // ─────────────────────────────────────────────────────────
  // Edit Command Parsing & Application
  // ─────────────────────────────────────────────────────────

  /// Pattern to match ```doc_edits ... ``` fenced blocks in LLM output.
  static final _editBlockPattern = RegExp(
    r'```doc_edits\s*\n([\s\S]*?)```',
    multiLine: true,
  );

  /// Parse an LLM response, extracting edit commands and conversational text.
  static DocEditParseResult parseEditCommands(String response) {
    final matches = _editBlockPattern.allMatches(response);
    if (matches.isEmpty) {
      return DocEditParseResult(chatText: response, commands: []);
    }

    final commands = <DocEditCommand>[];
    var chatText = response;

    for (final match in matches) {
      // Remove the edit block from chat display text
      chatText = chatText.replaceFirst(match.group(0)!, '');

      final jsonStr = match.group(1)!.trim();
      try {
        final parsed = jsonDecode(jsonStr);
        if (parsed is List) {
          for (final item in parsed) {
            if (item is Map<String, dynamic>) {
              final cmd = _parseCommand(item);
              if (cmd != null) commands.add(cmd);
            }
          }
        }
      } catch (_) {
        // Try line-by-line JSON parsing (some LLMs emit one JSON per line)
        for (final line in jsonStr.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
          try {
            final item = jsonDecode(trimmed);
            if (item is Map<String, dynamic>) {
              final cmd = _parseCommand(item);
              if (cmd != null) commands.add(cmd);
            }
          } catch (_) {}
        }
      }
    }

    // Clean up extra whitespace from stripping edit blocks
    chatText = chatText.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    return DocEditParseResult(chatText: chatText, commands: commands);
  }

  static DocEditCommand? _parseCommand(Map<String, dynamic> json) {
    final opStr = (json['op'] as String?)?.toLowerCase();
    if (opStr == null) return null;

    DocEditOp? op;
    switch (opStr) {
      case 'insert_after':
        op = DocEditOp.insertAfter;
      case 'insert_before':
        op = DocEditOp.insertBefore;
      case 'replace':
        op = DocEditOp.replace;
      case 'delete':
        op = DocEditOp.delete;
      case 'append':
        op = DocEditOp.append;
      default:
        return null;
    }

    final ref = json['ref'] as int?;
    final content = json['content'] as String?;

    return DocEditCommand(op: op, ref: ref, content: content);
  }

  /// Apply a list of edit commands to a document's blocks.
  /// Returns the new block list and a human-readable summary.
  static ({List<DocBlock> blocks, List<String> summary}) applyEditCommands(
    List<DocBlock> currentBlocks,
    List<DocEditCommand> commands,
  ) {
    var blocks = List<DocBlock>.from(currentBlocks);
    final summary = <String>[];

    // Process commands in reverse-ref order for inserts/deletes
    // so that indices don't shift under us.
    // But we need to respect the user's intended order, so we process
    // sequentially and adjust indices as we go.
    var indexOffset = 0;

    for (final cmd in commands) {
      final adjustedRef = (cmd.ref ?? -1) + indexOffset;

      switch (cmd.op) {
        case DocEditOp.insertAfter:
          if (cmd.content == null) continue;
          final newBlocks = parseMarkdownToBlocks(cmd.content!);
          if (newBlocks.isEmpty) continue;
          final insertAt = (adjustedRef + 1).clamp(0, blocks.length);
          blocks.insertAll(insertAt, newBlocks);
          indexOffset += newBlocks.length;
          final label = adjustedRef >= 0 && adjustedRef < blocks.length
              ? _blockLabel(blocks[adjustedRef])
              : 'end';
          summary.add('Inserted ${newBlocks.length} block(s) after "$label"');

        case DocEditOp.insertBefore:
          if (cmd.content == null) continue;
          final newBlocks = parseMarkdownToBlocks(cmd.content!);
          if (newBlocks.isEmpty) continue;
          final insertAt = adjustedRef.clamp(0, blocks.length);
          blocks.insertAll(insertAt, newBlocks);
          indexOffset += newBlocks.length;
          final label = insertAt < blocks.length
              ? _blockLabel(blocks[insertAt + newBlocks.length])
              : 'start';
          summary.add('Inserted ${newBlocks.length} block(s) before "$label"');

        case DocEditOp.replace:
          if (cmd.content == null) continue;
          if (adjustedRef < 0 || adjustedRef >= blocks.length) continue;
          final oldLabel = _blockLabel(blocks[adjustedRef]);
          final newBlocks = parseMarkdownToBlocks(cmd.content!);
          blocks.removeAt(adjustedRef);
          blocks.insertAll(adjustedRef, newBlocks);
          indexOffset += newBlocks.length - 1;
          summary.add('Replaced "$oldLabel" with ${newBlocks.length} block(s)');

        case DocEditOp.delete:
          if (adjustedRef < 0 || adjustedRef >= blocks.length) continue;
          final label = _blockLabel(blocks[adjustedRef]);
          blocks.removeAt(adjustedRef);
          indexOffset -= 1;
          summary.add('Deleted "$label"');

        case DocEditOp.append:
          if (cmd.content == null) continue;
          final newBlocks = parseMarkdownToBlocks(cmd.content!);
          if (newBlocks.isEmpty) continue;
          blocks.addAll(newBlocks);
          summary.add('Appended ${newBlocks.length} block(s) to document');
      }
    }

    return (blocks: blocks, summary: summary);
  }

  /// Short label for a block (used in edit summaries).
  static String _blockLabel(DocBlock block) {
    final text = block.content.length > 35
        ? '${block.content.substring(0, 35)}...'
        : block.content;
    return text.isEmpty ? block.typeLabel : text;
  }

  /// Convert DocxNode elements (from docx_creator AST) to DocBlocks.
  static List<DocBlock> _elementsToBlocks(List<DocxNode> elements) {
    final blocks = <DocBlock>[];

    for (final element in elements) {
      if (element is DocxParagraph) {
        final text = _extractParagraphText(element);
        final styleId = element.styleId?.toLowerCase() ?? '';

        if (element.pageBreakBefore) {
          blocks.add(const DocBlock(
            type: DocBlockType.pageBreak,
            content: '',
          ));
        }

        if (text.trim().isEmpty && !element.pageBreakBefore) continue;

        if (styleId.contains('heading1') || styleId == 'heading 1') {
          blocks.add(DocBlock(type: DocBlockType.heading1, content: text));
        } else if (styleId.contains('heading2') || styleId == 'heading 2') {
          blocks.add(DocBlock(type: DocBlockType.heading2, content: text));
        } else if (styleId.contains('heading3') || styleId == 'heading 3') {
          blocks.add(DocBlock(type: DocBlockType.heading3, content: text));
        } else {
          blocks.add(DocBlock(type: DocBlockType.paragraph, content: text));
        }
      } else if (element is DocxList) {
        final items = element.items
            .map((item) => _extractInlineText(item.children))
            .toList();
        final content = items.join('\n');
        blocks.add(DocBlock(
          type: element.isOrdered
              ? DocBlockType.numberedList
              : DocBlockType.bulletList,
          content: content,
        ));
      } else if (element is DocxTable) {
        final tableData = _extractTableData(element);
        blocks.add(DocBlock(
          type: DocBlockType.table,
          content: tableData
              .map((row) => row.join(' | '))
              .join('\n'),
          tableData: tableData,
        ));
      }
    }

    return blocks;
  }

  /// Extract plain text from a paragraph's inline children.
  static String _extractParagraphText(DocxParagraph paragraph) {
    return _extractInlineText(paragraph.children);
  }

  /// Extract plain text from a list of inline elements.
  static String _extractInlineText(List<DocxInline> inlines) {
    final buf = StringBuffer();
    for (final inline in inlines) {
      if (inline is DocxText) {
        buf.write(inline.content);
      }
    }
    return buf.toString();
  }

  /// Extract 2D string data from a table.
  static List<List<String>> _extractTableData(DocxTable table) {
    final rows = <List<String>>[];
    for (final row in table.rows) {
      final cells = <String>[];
      for (final cell in row.cells) {
        final buf = StringBuffer();
        for (final child in cell.children) {
          if (child is DocxParagraph) {
            buf.write(_extractParagraphText(child));
          }
        }
        cells.add(buf.toString());
      }
      rows.add(cells);
    }
    return rows;
  }
}
