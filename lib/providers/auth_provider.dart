import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/encryption_service.dart';

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(encryptionServiceProvider));
});

enum AuthStatus { unknown, noPassword, locked, unlocked }

class AuthState {
  final AuthStatus status;
  final String? error;

  const AuthState({required this.status, this.error});

  AuthState copyWith({AuthStatus? status, String? error}) {
    return AuthState(
      status: status ?? this.status,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final EncryptionService _encryption;

  AuthNotifier(this._encryption)
      : super(const AuthState(status: AuthStatus.unknown)) {
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPassword = prefs.getString('password_hash') != null;
    state = AuthState(
      status: hasPassword ? AuthStatus.locked : AuthStatus.noPassword,
    );
  }

  Future<bool> createPassword(String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salt = EncryptionService.generateSalt();
      final hash = _encryption.hashPassword(password, salt);

      await prefs.setString('password_salt', salt);
      await prefs.setString('password_hash', hash);

      _encryption.deriveKey(password, salt);
      state = const AuthState(status: AuthStatus.unlocked);
      return true;
    } catch (e) {
      state = AuthState(status: AuthStatus.noPassword, error: e.toString());
      return false;
    }
  }

  Future<bool> unlock(String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salt = prefs.getString('password_salt');
      final storedHash = prefs.getString('password_hash');

      if (salt == null || storedHash == null) {
        state = const AuthState(status: AuthStatus.noPassword);
        return false;
      }

      final hash = _encryption.hashPassword(password, salt);
      if (hash != storedHash) {
        state = const AuthState(
          status: AuthStatus.locked,
          error: 'Incorrect password',
        );
        return false;
      }

      _encryption.deriveKey(password, salt);
      state = const AuthState(status: AuthStatus.unlocked);
      return true;
    } catch (e) {
      state = AuthState(status: AuthStatus.locked, error: e.toString());
      return false;
    }
  }

  void lock() {
    _encryption.lock();
    state = const AuthState(status: AuthStatus.locked);
  }
}
