import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Renders AI markdown responses with styled code blocks and copy buttons.
///
/// Instead of using flutter_markdown (which has known assertion bugs with
/// custom builders and certain LLM outputs), this widget parses markdown
/// manually into blocks: paragraphs, code blocks, headers, and lists.
class MarkdownResponse extends StatelessWidget {
  final String data;
  final bool selectable;

  const MarkdownResponse({
    super.key,
    required this.data,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: blocks.map((b) => _buildBlock(context, b)).toList(),
    );
  }

  Widget _buildBlock(BuildContext context, _Block block) {
    final theme = Theme.of(context);

    switch (block.type) {
      case _BlockType.code:
        return _CodeBlock(
          code: block.content,
          language: block.meta,
        );
      case _BlockType.heading:
        final level = block.meta ?? '1';
        final style = switch (level) {
          '1' => theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
          '2' => theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
          _ => theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        };
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: selectable
              ? SelectableText(block.content, style: style)
              : Text(block.content, style: style),
        );
      case _BlockType.blockquote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
                width: 3,
              ),
            ),
          ),
          child: _RichLine(
            text: block.content,
            style:
                theme.textTheme.bodyMedium?.copyWith(height: 1.5) ??
                    const TextStyle(),
            selectable: selectable,
            theme: theme,
          ),
        );
      case _BlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: _RichLine(
            text: block.content,
            style:
                theme.textTheme.bodyMedium?.copyWith(height: 1.5) ??
                    const TextStyle(),
            selectable: selectable,
            theme: theme,
          ),
        );
    }
  }

  /// Parse markdown text into blocks (code blocks, headings, paragraphs).
  static List<_Block> _parseBlocks(String input) {
    final blocks = <_Block>[];
    final lines = input.split('\n');
    final buffer = <String>[];
    var inCode = false;
    String? codeLang;

    void flushParagraph() {
      if (buffer.isEmpty) return;
      final text = buffer.join('\n').trim();
      if (text.isNotEmpty) {
        blocks.add(_Block(_BlockType.paragraph, text));
      }
      buffer.clear();
    }

    for (final line in lines) {
      // Fenced code block toggle
      if (line.trimLeft().startsWith('```')) {
        if (!inCode) {
          flushParagraph();
          inCode = true;
          final langPart = line.trimLeft().substring(3).trim();
          codeLang = langPart.isNotEmpty ? langPart : null;
        } else {
          blocks.add(_Block(
            _BlockType.code,
            buffer.join('\n'),
            meta: codeLang,
          ));
          buffer.clear();
          inCode = false;
          codeLang = null;
        }
        continue;
      }

      if (inCode) {
        buffer.add(line);
        continue;
      }

      // Heading
      final headingMatch = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        flushParagraph();
        blocks.add(_Block(
          _BlockType.heading,
          headingMatch.group(2)!,
          meta: headingMatch.group(1)!.length.toString(),
        ));
        continue;
      }

      // Blockquote
      if (line.trimLeft().startsWith('> ')) {
        flushParagraph();
        blocks.add(_Block(
          _BlockType.blockquote,
          line.trimLeft().substring(2),
        ));
        continue;
      }

      // Empty line = paragraph break
      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }

      buffer.add(line);
    }

    // Flush remaining
    if (inCode) {
      // Unclosed code block — treat as code anyway
      blocks.add(_Block(
        _BlockType.code,
        buffer.join('\n'),
        meta: codeLang,
      ));
    } else {
      flushParagraph();
    }

    return blocks;
  }
}

enum _BlockType { paragraph, code, heading, blockquote }

class _Block {
  final _BlockType type;
  final String content;
  final String? meta; // language for code, level for heading

  _Block(this.type, this.content, {this.meta});
}

/// Renders inline markdown (bold, italic, code, links) as a RichText/
/// SelectableText.rich span tree.
class _RichLine extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool selectable;
  final ThemeData theme;

  const _RichLine({
    required this.text,
    required this.style,
    required this.selectable,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final spans = _parseInline(text, style);
    final textSpan = TextSpan(children: spans);
    return selectable
        ? SelectableText.rich(textSpan)
        : Text.rich(textSpan);
  }

  List<InlineSpan> _parseInline(String text, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    final codeStyle = GoogleFonts.firaCode(
      fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! - 1 : 12,
      height: baseStyle.height,
    );

    // Process inline formatting with a regex-based approach
    // Matches: `code`, **bold**, *italic*, _italic_, __bold__
    final pattern = RegExp(
      r'`([^`]+)`'           // inline code
      r'|\*\*(.+?)\*\*'      // bold
      r'|\*(.+?)\*'          // italic
      r'|__(.+?)__'          // bold (underscore)
      r'|_(.+?)_'            // italic (underscore)
    );

    var lastEnd = 0;

    for (final match in pattern.allMatches(text)) {
      // Add text before this match
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }

      if (match.group(1) != null) {
        // Inline code
        spans.add(TextSpan(
          text: match.group(1),
          style: codeStyle.copyWith(
            backgroundColor: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            color: theme.colorScheme.primary,
          ),
        ));
      } else if (match.group(2) != null || match.group(4) != null) {
        // Bold
        final boldText = match.group(2) ?? match.group(4)!;
        spans.add(TextSpan(
          text: boldText,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (match.group(3) != null || match.group(5) != null) {
        // Italic
        final italicText = match.group(3) ?? match.group(5)!;
        spans.add(TextSpan(
          text: italicText,
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      }

      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: baseStyle));
    }

    return spans;
  }
}

/// Styled fenced code block with language label and copy button.
class _CodeBlock extends StatefulWidget {
  final String code;
  final String? language;

  const _CodeBlock({
    required this.code,
    this.language,
  });

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final codeStyle = GoogleFonts.firaCode(fontSize: 13, height: 1.5);

    final bgColor = isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F5);
    final headerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            child: Row(
              children: [
                if (widget.language != null)
                  Text(
                    widget.language!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  height: 28,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: widget.code),
                      );
                      setState(() => _copied = true);
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _copied = false);
                      });
                    },
                    icon: Icon(
                      _copied ? Icons.check : Icons.copy,
                      size: 14,
                      color: _copied
                          ? Colors.green
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    label: Text(
                      _copied ? 'Copied!' : 'Copy',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _copied
                            ? Colors.green
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              widget.code,
              style: codeStyle.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
