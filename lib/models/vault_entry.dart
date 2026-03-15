class VaultEntry {
  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final String category;
  final String tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;

  VaultEntry({
    required this.id,
    required this.title,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.category = 'General',
    this.tags = '',
    required this.createdAt,
    required this.updatedAt,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isExpiringSoon =>
      expiresAt != null &&
      !isExpired &&
      expiresAt!.isBefore(DateTime.now().add(const Duration(days: 30)));

  VaultEntry copyWith({
    String? id,
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    String? category,
    String? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
  }) {
    return VaultEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'username': username,
      'password': password,
      'url': url,
      'notes': notes,
      'category': category,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  factory VaultEntry.fromMap(Map<String, dynamic> map) {
    return VaultEntry(
      id: map['id'] as String,
      title: map['title'] as String,
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      url: map['url'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      category: map['category'] as String? ?? 'General',
      tags: map['tags'] as String? ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      expiresAt: map['expiresAt'] != null
          ? DateTime.parse(map['expiresAt'] as String)
          : null,
    );
  }
}
