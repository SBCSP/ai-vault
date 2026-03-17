class Document {
  final String id;
  final String title;
  final String filePath;
  final String fileType; // 'txt', 'md'
  final int chunkCount;
  final String contentHash;
  final String tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastIndexedAt;

  Document({
    required this.id,
    required this.title,
    required this.filePath,
    this.fileType = 'txt',
    this.chunkCount = 0,
    this.contentHash = '',
    this.tags = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastIndexedAt,
  });

  Document copyWith({
    String? id,
    String? title,
    String? filePath,
    String? fileType,
    int? chunkCount,
    String? contentHash,
    String? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastIndexedAt,
    bool clearLastIndexedAt = false,
  }) {
    return Document(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      fileType: fileType ?? this.fileType,
      chunkCount: chunkCount ?? this.chunkCount,
      contentHash: contentHash ?? this.contentHash,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastIndexedAt:
          clearLastIndexedAt ? null : (lastIndexedAt ?? this.lastIndexedAt),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'filePath': filePath,
      'fileType': fileType,
      'chunkCount': chunkCount,
      'contentHash': contentHash,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastIndexedAt': lastIndexedAt?.toIso8601String(),
    };
  }

  factory Document.fromMap(Map<String, dynamic> map) {
    return Document(
      id: map['id'] as String,
      title: map['title'] as String,
      filePath: map['filePath'] as String,
      fileType: map['fileType'] as String? ?? 'txt',
      chunkCount: map['chunkCount'] as int? ?? 0,
      contentHash: map['contentHash'] as String? ?? '',
      tags: map['tags'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      lastIndexedAt: map['lastIndexedAt'] != null
          ? DateTime.parse(map['lastIndexedAt'] as String)
          : null,
    );
  }
}
