import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/sha256.dart';

import '../models/note.dart';
import '../models/vault_entry.dart';

class EmbeddingService {
  final String serverUrl;
  final String model;

  EmbeddingService({
    required this.serverUrl,
    required this.model,
  });

  /// Generate an embedding vector for the given text using Ollama's /api/embed.
  Future<List<double>?> generateEmbedding(String text) async {
    try {
      final response = await http
          .post(
            Uri.parse('$serverUrl/api/embed'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'input': text,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final embeddings = json['embeddings'] as List<dynamic>?;
      if (embeddings == null || embeddings.isEmpty) return null;

      final first = embeddings[0] as List<dynamic>;
      return first.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return null;
    }
  }

  /// Cosine similarity between two vectors. Returns value in [-1, 1].
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0) return 0.0;
    return dotProduct / denominator;
  }

  /// Build embeddable text for a vault entry.
  /// Excludes password — we match on metadata, not secrets.
  static String buildEntryText(VaultEntry entry) {
    final parts = <String>[
      entry.title,
      if (entry.category.isNotEmpty) 'Category: ${entry.category}',
      if (entry.username.isNotEmpty) 'Username: ${entry.username}',
      if (entry.url.isNotEmpty) 'URL: ${entry.url}',
      if (entry.tags.isNotEmpty) 'Tags: ${entry.tags}',
      if (entry.notes.isNotEmpty) 'Notes: ${entry.notes}',
    ];
    return parts.join('\n');
  }

  /// Build embeddable text for a note.
  static String buildNoteText(Note note) {
    final bodyPreview =
        note.body.length > 2000 ? note.body.substring(0, 2000) : note.body;
    final parts = <String>[
      note.title,
      if (note.tags.isNotEmpty) 'Tags: ${note.tags}',
      if (bodyPreview.isNotEmpty) bodyPreview,
    ];
    return parts.join('\n');
  }

  /// Build embeddable text for a document chunk.
  /// Prefixes with document title for better semantic context.
  static String buildChunkText(String documentTitle, String chunkContent) {
    return 'Document: $documentTitle\n\n$chunkContent';
  }

  /// SHA-256 hash of text content to detect changes.
  static String computeContentHash(String text) {
    final digest = SHA256Digest();
    final bytes = utf8.encode(text);
    final hash = digest.process(Uint8List.fromList(bytes));
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
