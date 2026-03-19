import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart' as db;
import '../models/chat_session.dart';
import '../services/ai_service.dart';
import 'audit_provider.dart';
import 'vault_provider.dart';

/// Watches all chat sessions from the database, sorted by updatedAt desc.
final chatSessionsProvider = StreamProvider<List<ChatSession>>((ref) {
  final database = ref.read(databaseProvider);

  return database.watchAllChatSessions().map((sessions) {
    return sessions.map((s) => _mapSession(s)).toList();
  });
});

/// Actions for saving, updating, and deleting chat sessions.
final chatSessionActionsProvider = Provider<ChatSessionActions>((ref) {
  return ChatSessionActions(
    db: ref.read(databaseProvider),
    audit: ref.read(auditLoggerProvider),
  );
});

ChatSession _mapSession(db.ChatSession s) {
  return ChatSession(
    id: s.id,
    title: s.title,
    messages: ChatSession.parseMessages(s.messages),
    isIndexed: s.isIndexed,
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
  );
}

class ChatSessionActions {
  final db.AppDatabase _db;
  final AuditLogger _audit;
  static const _uuid = Uuid();

  ChatSessionActions({required db.AppDatabase db, required AuditLogger audit})
      : _db = db,
        _audit = audit;

  /// Save a new chat session from in-memory ChatMessages.
  /// Returns the new session ID.
  Future<String> saveSession(
    String title,
    List<ChatMessage> messages,
  ) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    final sessionMessages = messages
        .map((m) => ChatSessionMessage(
              text: m.text,
              isUser: m.isUser,
              timestamp: now,
            ))
        .toList();

    final session = ChatSession(
      id: id,
      title: title,
      messages: sessionMessages,
      createdAt: now,
      updatedAt: now,
    );

    await _db.insertChatSession(db.ChatSessionsCompanion.insert(
      id: id,
      title: title,
      messages: session.messagesJson,
      createdAt: now,
      updatedAt: now,
    ));

    await _audit.log(
      action: AuditAction.chatSaved,
      targetType: 'chat',
      targetId: id,
      targetName: title,
    );

    return id;
  }

  /// Mark a session as indexed.
  Future<void> markIndexed(String id) async {
    await _db.updateChatSession(db.ChatSessionsCompanion(
      id: Value(id),
      isIndexed: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Delete a session.
  Future<void> deleteSession(String id) async {
    await _audit.log(
      action: AuditAction.chatDeleted,
      targetType: 'chat',
      targetId: id,
    );
    await _db.deleteChatSession(id);
  }
}
