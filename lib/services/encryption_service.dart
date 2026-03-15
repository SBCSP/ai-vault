import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/export.dart' as pc;

class EncryptionService {
  Key? _key;

  bool get isUnlocked => _key != null;

  void deriveKey(String masterPassword, String salt) {
    final saltBytes = Uint8List.fromList(utf8.encode(salt));
    final passwordBytes = Uint8List.fromList(utf8.encode(masterPassword));

    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(saltBytes, 100000, 32));

    final keyBytes = derivator.process(passwordBytes);
    _key = Key(keyBytes);
  }

  String encrypt(String plaintext) {
    if (_key == null) throw StateError('Encryption key not derived');
    if (plaintext.isEmpty) return '';

    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(_key!, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    return '${iv.base64}:${encrypted.base64}';
  }

  String decrypt(String ciphertext) {
    if (_key == null) throw StateError('Encryption key not derived');
    if (ciphertext.isEmpty) return '';

    final parts = ciphertext.split(':');
    if (parts.length != 2) throw FormatException('Invalid ciphertext format');

    final iv = IV.fromBase64(parts[0]);
    final encrypted = Encrypted.fromBase64(parts[1]);
    final encrypter = Encrypter(AES(_key!, mode: AESMode.cbc));

    return encrypter.decrypt(encrypted, iv: iv);
  }

  void lock() {
    _key = null;
  }

  static String generateSalt() {
    final random = Random.secure();
    final salt = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(salt);
  }

  String hashPassword(String password, String salt) {
    final saltBytes = Uint8List.fromList(utf8.encode(salt));
    final passwordBytes =
        Uint8List.fromList(utf8.encode('$salt:$password:verify'));

    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(saltBytes, 10000, 32));

    final hash = derivator.process(passwordBytes);
    return base64Url.encode(hash);
  }
}
