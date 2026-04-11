/// The type of content a document block represents.
enum DocBlockType {
  heading1,
  heading2,
  heading3,
  paragraph,
  bulletList,
  numberedList,
  table,
  pageBreak,
}

/// A single block of content in a document.
/// The document is represented as an ordered list of these blocks.
class DocBlock {
  final DocBlockType type;
  final String content;

  /// For tables: rows of cells. Each inner list is one row.
  final List<List<String>>? tableData;

  const DocBlock({
    required this.type,
    required this.content,
    this.tableData,
  });

  DocBlock copyWith({
    DocBlockType? type,
    String? content,
    List<List<String>>? tableData,
  }) {
    return DocBlock(
      type: type ?? this.type,
      content: content ?? this.content,
      tableData: tableData ?? this.tableData,
    );
  }

  /// Convert block to plain text for LLM context.
  String toPlainText() {
    switch (type) {
      case DocBlockType.heading1:
        return '# $content';
      case DocBlockType.heading2:
        return '## $content';
      case DocBlockType.heading3:
        return '### $content';
      case DocBlockType.paragraph:
        return content;
      case DocBlockType.bulletList:
        return content
            .split('\n')
            .map((line) => '- $line')
            .join('\n');
      case DocBlockType.numberedList:
        final lines = content.split('\n');
        return lines
            .asMap()
            .entries
            .map((e) => '${e.key + 1}. ${e.value}')
            .join('\n');
      case DocBlockType.table:
        if (tableData == null || tableData!.isEmpty) return content;
        final buf = StringBuffer();
        for (var i = 0; i < tableData!.length; i++) {
          buf.writeln('| ${tableData![i].join(' | ')} |');
          if (i == 0) {
            buf.writeln('| ${tableData![0].map((_) => '---').join(' | ')} |');
          }
        }
        return buf.toString().trimRight();
      case DocBlockType.pageBreak:
        return '---';
    }
  }

  /// Human-readable type label.
  String get typeLabel {
    switch (type) {
      case DocBlockType.heading1:
        return 'Heading 1';
      case DocBlockType.heading2:
        return 'Heading 2';
      case DocBlockType.heading3:
        return 'Heading 3';
      case DocBlockType.paragraph:
        return 'Paragraph';
      case DocBlockType.bulletList:
        return 'Bullet List';
      case DocBlockType.numberedList:
        return 'Numbered List';
      case DocBlockType.table:
        return 'Table';
      case DocBlockType.pageBreak:
        return 'Page Break';
    }
  }
}
