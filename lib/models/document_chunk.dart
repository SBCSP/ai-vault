class DocumentChunk {
  final String id;
  final String documentId;
  final int chunkIndex;
  final String content;
  final String contentHash;
  final DateTime createdAt;

  DocumentChunk({
    required this.id,
    required this.documentId,
    required this.chunkIndex,
    required this.content,
    this.contentHash = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'documentId': documentId,
      'chunkIndex': chunkIndex,
      'content': content,
      'contentHash': contentHash,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory DocumentChunk.fromMap(Map<String, dynamic> map) {
    return DocumentChunk(
      id: map['id'] as String,
      documentId: map['documentId'] as String,
      chunkIndex: map['chunkIndex'] as int,
      content: map['content'] as String,
      contentHash: map['contentHash'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
