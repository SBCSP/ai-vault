import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'embedding_service.dart';

/// Result of scanning a directory for supported files.
class DirectoryScanResult {
  final List<File> supportedFiles;
  final int skippedCount;
  final List<String> skippedExtensions;

  const DirectoryScanResult({
    required this.supportedFiles,
    required this.skippedCount,
    required this.skippedExtensions,
  });
}

class DocumentService {
  /// Supported file extensions for indexing.
  static const supportedExtensions = [
    '.txt', '.md', '.markdown', '.json', '.yaml', '.yml', '.csv', '.log', '.pdf',
  ];

  /// Scan a directory recursively for supported files.
  static Future<DirectoryScanResult> scanDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return const DirectoryScanResult(
        supportedFiles: [],
        skippedCount: 0,
        skippedExtensions: [],
      );
    }

    final supported = <File>[];
    var skipped = 0;
    final skippedExts = <String>{};

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (supportedExtensions.contains(ext)) {
          supported.add(entity);
        } else {
          skipped++;
          if (ext.isNotEmpty) skippedExts.add(ext);
        }
      }
    }

    // Sort by filename for consistent ordering
    supported.sort((a, b) =>
        p.basename(a.path).toLowerCase().compareTo(
            p.basename(b.path).toLowerCase()));

    return DirectoryScanResult(
      supportedFiles: supported,
      skippedCount: skipped,
      skippedExtensions: skippedExts.toList()..sort(),
    );
  }

  /// Read file content from disk. Returns null if file doesn't exist.
  /// Supports text files and PDFs (extracts text from PDFs).
  /// Throws on permission/access errors so callers can handle them.
  static Future<String?> readFileContent(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.pdf') {
      return _extractPdfText(file);
    }

    // Let FileSystemException propagate so callers know about
    // permission issues (e.g. macOS sandbox blocking access)
    return await file.readAsString();
  }

  /// Extract text from a PDF file using Syncfusion PDF.
  static Future<String?> _extractPdfText(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText();
      document.dispose();
      return text.isNotEmpty ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// Check if file exists on disk.
  static Future<bool> fileExists(String filePath) async {
    return File(filePath).exists();
  }

  /// Check if file has changed since last index by comparing content hash.
  static Future<bool> hasFileChanged(
      String filePath, String lastHash) async {
    final content = await readFileContent(filePath);
    if (content == null) return false;
    return EmbeddingService.computeContentHash(content) != lastHash;
  }

  /// Split text into chunks of ~chunkSize characters with overlap.
  /// Tries to break at paragraph or sentence boundaries.
  static List<String> chunkText(
    String text, {
    int chunkSize = 1000,
    int overlap = 200,
  }) {
    if (text.isEmpty) return [];
    if (text.length <= chunkSize) return [text];

    final chunks = <String>[];
    var start = 0;

    while (start < text.length) {
      var end = start + chunkSize;

      if (end >= text.length) {
        chunks.add(text.substring(start));
        break;
      }

      // Try to break at a paragraph or sentence boundary
      final segment = text.substring(start, end);
      final lastParagraph = segment.lastIndexOf('\n\n');
      final lastSentence = segment.lastIndexOf('. ');
      final lastNewline = segment.lastIndexOf('\n');

      if (lastParagraph > chunkSize * 0.5) {
        end = start + lastParagraph + 2;
      } else if (lastSentence > chunkSize * 0.5) {
        end = start + lastSentence + 2;
      } else if (lastNewline > chunkSize * 0.5) {
        end = start + lastNewline + 1;
      }

      chunks.add(text.substring(start, end));
      start = end - overlap;
      if (start < 0) start = 0;
    }

    return chunks;
  }

  /// Detect file type from extension.
  static String detectFileType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.md':
      case '.markdown':
        return 'md';
      case '.txt':
        return 'txt';
      case '.log':
        return 'txt';
      case '.json':
        return 'json';
      case '.yaml':
      case '.yml':
        return 'yaml';
      case '.csv':
        return 'csv';
      case '.pdf':
        return 'pdf';
      default:
        return 'txt';
    }
  }

  /// Get file size in bytes. Returns 0 if file doesn't exist.
  static Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Format file size for display.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
  }
}
