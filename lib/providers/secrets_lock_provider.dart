import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audit_provider.dart';

/// Whether the secrets vault is locked (inaccessible to UI and LLM).
/// This is separate from the master vault lock — it controls secrets-only access.
final secretsLockProvider =
    StateNotifierProvider<SecretsLockNotifier, bool>((ref) {
  return SecretsLockNotifier(ref);
});

class SecretsLockNotifier extends StateNotifier<bool> {
  final Ref _ref;
  static const _key = 'secrets_locked';

  SecretsLockNotifier(this._ref) : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> toggle() async {
    final newValue = !state;
    state = newValue;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, newValue);

    await _ref.read(auditLoggerProvider).log(
      action: newValue
          ? AuditAction.secretsLocked
          : AuditAction.secretsUnlocked,
    );
  }

  Future<void> lock() async {
    if (state) return;
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    await _ref.read(auditLoggerProvider).log(
      action: AuditAction.secretsLocked,
    );
  }

  Future<void> unlock() async {
    if (!state) return;
    state = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, false);
    await _ref.read(auditLoggerProvider).log(
      action: AuditAction.secretsUnlocked,
    );
  }
}
