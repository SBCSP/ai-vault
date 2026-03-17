import 'dart:convert';

class ChatSessionMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  const ChatSessionMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatSessionMessage.fromMap(Map<String, dynamic> map) {
    return ChatSessionMessage(
      text: map['text'] as String,
      isUser: map['isUser'] as bool,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

class ChatSession {
  final String id;
  final String title;
  final List<ChatSessionMessage> messages;
  final bool isIndexed;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    this.isIndexed = false,
    required this.createdAt,
    required this.updatedAt,
  });

  ChatSession copyWith({
    String? id,
    String? title,
    List<ChatSessionMessage>? messages,
    bool? isIndexed,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      isIndexed: isIndexed ?? this.isIndexed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Encode messages to JSON string for Drift text column.
  String get messagesJson =>
      jsonEncode(messages.map((m) => m.toMap()).toList());

  /// Decode messages from JSON string.
  static List<ChatSessionMessage> parseMessages(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((m) => ChatSessionMessage.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  /// Preview text: first user message, truncated.
  String get preview {
    final firstUser = messages.where((m) => m.isUser).firstOrNull;
    if (firstUser == null) return '';
    return firstUser.text.length > 80
        ? '${firstUser.text.substring(0, 80)}...'
        : firstUser.text;
  }

  /// Count of messages by role.
  int get userMessageCount => messages.where((m) => m.isUser).length;
  int get assistantMessageCount => messages.where((m) => !m.isUser).length;
}
