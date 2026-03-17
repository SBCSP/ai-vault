import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

/// Manages a self-signed TLS certificate for the Vault API.
///
/// Generates RSA 2048-bit keys and a self-signed X.509 v3 certificate
/// entirely in Dart using PointyCastle — no external tools required.
/// Works on macOS, Windows, and Linux.
///
/// Certificate and key are stored in PEM format in the application
/// support directory and reused on subsequent launches.
class CertificateService {
  static const _certFileName = 'vault_api_cert.pem';
  static const _keyFileName = 'vault_api_key.pem';
  static const _metaFileName = 'vault_api_cert.meta';
  static const _validityDays = 3650; // 10 years

  // ───── Path helpers ─────

  static Future<Directory> _certsDir() async {
    final appDir = await getApplicationSupportDirectory();
    final certsDir = Directory('${appDir.path}/certs');
    if (!await certsDir.exists()) {
      await certsDir.create(recursive: true);
    }
    return certsDir;
  }

  static Future<String> get certPath async {
    final dir = await _certsDir();
    return '${dir.path}/$_certFileName';
  }

  static Future<String> get keyPath async {
    final dir = await _certsDir();
    return '${dir.path}/$_keyFileName';
  }

  static Future<String> get _metaPath async {
    final dir = await _certsDir();
    return '${dir.path}/$_metaFileName';
  }

  // ───── Public API ─────

  static Future<bool> certificateExists() async {
    final cert = File(await certPath);
    final key = File(await keyPath);
    return await cert.exists() && await key.exists();
  }

  /// Ensures a valid certificate exists. Generates one if missing or expired.
  static Future<bool> ensureCertificate() async {
    if (await certificateExists()) {
      if (await _isCertificateValid()) {
        return true;
      }
      await _deleteCertificate();
    }
    return _generateCertificate();
  }

  /// Returns certificate metadata for display in the UI.
  static Future<Map<String, String>> getCertificateInfo() async {
    try {
      final metaFile = File(await _metaPath);
      if (!await metaFile.exists()) return {};

      final lines = await metaFile.readAsLines();
      final info = <String, String>{};
      for (final line in lines) {
        final idx = line.indexOf('=');
        if (idx > 0) {
          info[line.substring(0, idx)] = line.substring(idx + 1);
        }
      }
      return info;
    } catch (_) {
      return {};
    }
  }

  // ───── Certificate generation (pure Dart) ─────

  static Future<bool> _generateCertificate() async {
    try {
      // 1. Generate RSA 2048 key pair
      final keyPair = _generateRSAKeyPair();
      final publicKey = keyPair.publicKey as RSAPublicKey;
      final privateKey = keyPair.privateKey as RSAPrivateKey;

      // 2. Build self-signed X.509 v3 certificate
      final now = DateTime.now().toUtc();
      final notAfter = now.add(Duration(days: _validityDays));
      final serialNumber = _randomSerialNumber();

      final tbsCert = _buildTBSCertificate(
        serialNumber: serialNumber,
        notBefore: now,
        notAfter: notAfter,
        publicKey: publicKey,
      );

      // 3. Sign with SHA-256 + RSA
      final signature = _signData(tbsCert, privateKey);

      // 4. Wrap in X.509 Certificate structure
      final cert = _buildCertificate(tbsCert, signature);

      // 5. Encode to PEM
      final certPem = _toPem(cert, 'CERTIFICATE');
      final keyPem = _toPem(_encodePrivateKey(privateKey), 'RSA PRIVATE KEY');

      // 6. Write files
      final certFile = File(await certPath);
      final keyFile = File(await keyPath);
      await certFile.writeAsString(certPem);
      await keyFile.writeAsString(keyPem);

      // 7. Write metadata for UI display
      final fingerprint = _sha1Fingerprint(cert);
      final metaFile = File(await _metaPath);
      await metaFile.writeAsString(
        'subject=CN=AI VaultIO Local API, O=AI VaultIO\n'
        'expires=${notAfter.toIso8601String()}\n'
        'fingerprint=$fingerprint\n'
        'generated=${now.toIso8601String()}\n',
      );

      return true;
    } catch (_) {
      await _deleteCertificate();
      return false;
    }
  }

  static Future<bool> _isCertificateValid() async {
    try {
      final info = await getCertificateInfo();
      final expiresStr = info['expires'];
      if (expiresStr == null) return false;

      final expires = DateTime.parse(expiresStr);
      // Valid if more than 24 hours remain
      return expires.isAfter(DateTime.now().add(const Duration(hours: 24)));
    } catch (_) {
      return false;
    }
  }

  static Future<void> _deleteCertificate() async {
    try {
      for (final path in [await certPath, await keyPath, await _metaPath]) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  // ───── RSA Key Generation ─────

  static AsymmetricKeyPair<PublicKey, PrivateKey> _generateRSAKeyPair() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ));

    return keyGen.generateKeyPair();
  }

  // ───── ASN.1 DER Encoding Primitives ─────

  static Uint8List _derTag(int tag, Uint8List content) {
    final len = content.length;
    List<int> header;

    if (len < 0x80) {
      header = [tag, len];
    } else if (len < 0x100) {
      header = [tag, 0x81, len];
    } else if (len < 0x10000) {
      header = [tag, 0x82, len >> 8, len & 0xFF];
    } else {
      header = [tag, 0x83, len >> 16, (len >> 8) & 0xFF, len & 0xFF];
    }

    return Uint8List.fromList([...header, ...content]);
  }

  static Uint8List _derSequence(List<Uint8List> items) {
    final content = items.fold<List<int>>([], (a, b) => [...a, ...b]);
    return _derTag(0x30, Uint8List.fromList(content));
  }

  static Uint8List _derSet(List<Uint8List> items) {
    final content = items.fold<List<int>>([], (a, b) => [...a, ...b]);
    return _derTag(0x31, Uint8List.fromList(content));
  }

  static Uint8List _derInteger(BigInt value) {
    var bytes = _bigIntToBytes(value);
    // Ensure positive encoding (add leading zero if high bit set)
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    return _derTag(0x02, bytes);
  }

  static Uint8List _derOid(List<int> oid) {
    final encoded = <int>[];
    // First two components combined
    encoded.add(oid[0] * 40 + oid[1]);
    for (var i = 2; i < oid.length; i++) {
      _encodeOidComponent(encoded, oid[i]);
    }
    return _derTag(0x06, Uint8List.fromList(encoded));
  }

  static void _encodeOidComponent(List<int> out, int value) {
    if (value < 128) {
      out.add(value);
      return;
    }
    final bytes = <int>[];
    var v = value;
    bytes.add(v & 0x7F);
    v >>= 7;
    while (v > 0) {
      bytes.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.addAll(bytes.reversed);
  }

  static Uint8List _derBitString(Uint8List data) {
    // Prepend 0 byte for "unused bits" count
    return _derTag(0x03, Uint8List.fromList([0, ...data]));
  }

  static Uint8List _derOctetString(Uint8List data) {
    return _derTag(0x04, data);
  }

  static Uint8List _derUtf8String(String s) {
    return _derTag(0x0C, Uint8List.fromList(s.codeUnits));
  }

  static Uint8List _derPrintableString(String s) {
    return _derTag(0x13, Uint8List.fromList(s.codeUnits));
  }

  static Uint8List _derUtcTime(DateTime dt) {
    final utc = dt.toUtc();
    final s = '${_pad2(utc.year % 100)}${_pad2(utc.month)}${_pad2(utc.day)}'
        '${_pad2(utc.hour)}${_pad2(utc.minute)}${_pad2(utc.second)}Z';
    return _derTag(0x17, Uint8List.fromList(s.codeUnits));
  }

  static Uint8List _derExplicit(int tagNumber, Uint8List content) {
    return _derTag(0xA0 | tagNumber, content);
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  // ───── X.509 Certificate Building ─────

  /// OIDs
  static final _oidSha256WithRsa = [1, 2, 840, 113549, 1, 1, 11];
  static final _oidRsaEncryption = [1, 2, 840, 113549, 1, 1, 1];
  static final _oidCommonName = [2, 5, 4, 3];
  static final _oidOrganization = [2, 5, 4, 10];
  static final _oidSubjectAltName = [2, 5, 29, 17];

  static Uint8List _buildAlgorithmIdentifier(List<int> oid) {
    return _derSequence([
      _derOid(oid),
      Uint8List.fromList([0x05, 0x00]), // NULL
    ]);
  }

  static Uint8List _buildName() {
    // Subject/Issuer: CN=AI VaultIO Local API, O=AI VaultIO
    return _derSequence([
      _derSet([
        _derSequence([_derOid(_oidCommonName), _derUtf8String('AI VaultIO Local API')]),
      ]),
      _derSet([
        _derSequence([_derOid(_oidOrganization), _derPrintableString('AI VaultIO')]),
      ]),
    ]);
  }

  static Uint8List _buildSubjectPublicKeyInfo(RSAPublicKey publicKey) {
    final rsaPublicKey = _derSequence([
      _derInteger(publicKey.modulus!),
      _derInteger(publicKey.publicExponent!),
    ]);

    return _derSequence([
      _buildAlgorithmIdentifier(_oidRsaEncryption),
      _derBitString(rsaPublicKey),
    ]);
  }

  static Uint8List _buildExtensions() {
    // Subject Alternative Name: DNS:localhost, IP:127.0.0.1
    final sanValue = _derSequence([
      // DNS:localhost (context tag 2)
      _derTag(0x82, Uint8List.fromList('localhost'.codeUnits)),
      // IP:127.0.0.1 (context tag 7)
      _derTag(0x87, Uint8List.fromList([127, 0, 0, 1])),
    ]);

    final sanExtension = _derSequence([
      _derOid(_oidSubjectAltName),
      _derOctetString(sanValue),
    ]);

    // Extensions wrapped in explicit tag [3]
    return _derExplicit(3, _derSequence([sanExtension]));
  }

  static Uint8List _buildTBSCertificate({
    required BigInt serialNumber,
    required DateTime notBefore,
    required DateTime notAfter,
    required RSAPublicKey publicKey,
  }) {
    final name = _buildName();

    return _derSequence([
      // Version: v3
      _derExplicit(0, _derInteger(BigInt.from(2))),
      // Serial number
      _derInteger(serialNumber),
      // Signature algorithm
      _buildAlgorithmIdentifier(_oidSha256WithRsa),
      // Issuer (same as subject — self-signed)
      name,
      // Validity
      _derSequence([
        _derUtcTime(notBefore),
        _derUtcTime(notAfter),
      ]),
      // Subject
      name,
      // Subject Public Key Info
      _buildSubjectPublicKeyInfo(publicKey),
      // Extensions
      _buildExtensions(),
    ]);
  }

  static Uint8List _buildCertificate(
      Uint8List tbsCertificate, Uint8List signature) {
    return _derSequence([
      tbsCertificate,
      _buildAlgorithmIdentifier(_oidSha256WithRsa),
      _derBitString(signature),
    ]);
  }

  // ───── RSA Private Key PKCS#1 Encoding ─────

  static Uint8List _encodePrivateKey(RSAPrivateKey key) {
    return _derSequence([
      _derInteger(BigInt.zero), // version
      _derInteger(key.modulus!),
      _derInteger(key.publicExponent!),
      _derInteger(key.privateExponent!),
      _derInteger(key.p!),
      _derInteger(key.q!),
      _derInteger(key.privateExponent! % (key.p! - BigInt.one)), // d mod (p-1)
      _derInteger(key.privateExponent! % (key.q! - BigInt.one)), // d mod (q-1)
      _derInteger(key.q!.modInverse(key.p!)), // q^-1 mod p
    ]);
  }

  // ───── Signing ─────

  static Uint8List _signData(Uint8List data, RSAPrivateKey privateKey) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final sig = signer.generateSignature(data);
    return sig.bytes;
  }

  // ───── Utilities ─────

  static BigInt _randomSerialNumber() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[0] &= 0x7F; // Ensure positive
    return BigInt.parse(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
  }

  static Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) return Uint8List.fromList([0]);

    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';

    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  static String _toPem(Uint8List der, String label) {
    final b64 = _base64Encode(der);
    final lines = <String>['-----BEGIN $label-----'];
    for (var i = 0; i < b64.length; i += 64) {
      lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }
    lines.add('-----END $label-----');
    lines.add(''); // trailing newline
    return lines.join('\n');
  }

  static String _base64Encode(Uint8List data) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final buf = StringBuffer();
    for (var i = 0; i < data.length; i += 3) {
      final b0 = data[i];
      final b1 = i + 1 < data.length ? data[i + 1] : 0;
      final b2 = i + 2 < data.length ? data[i + 2] : 0;
      buf.write(chars[(b0 >> 2) & 0x3F]);
      buf.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);
      buf.write(i + 1 < data.length ? chars[((b1 << 2) | (b2 >> 6)) & 0x3F] : '=');
      buf.write(i + 2 < data.length ? chars[b2 & 0x3F] : '=');
    }
    return buf.toString();
  }

  static String _sha1Fingerprint(Uint8List cert) {
    final digest = SHA1Digest().process(cert);
    return digest
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
}
