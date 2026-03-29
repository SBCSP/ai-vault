import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

/// Manages mTLS certificates for aiv_agent remote server authentication.
///
/// Generates a full certificate chain:
///   - CA certificate (signs both client and server certs)
///   - Client certificate + key (stored locally in AI VaultIO)
///   - Server certificate + key (bundled into the agent .rpm download)
///
/// All certificates are generated purely in Dart using PointyCastle.
class AgentCertificateService {
  static const _validityDays = 3650; // 10 years
  static const _keyBits = 2048;

  // ───── Directory / file helpers ─────

  static Future<Directory> _agentCertsDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/agent_certs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> _filePath(String name) async {
    final dir = await _agentCertsDir();
    return '${dir.path}/$name';
  }

  // Public paths
  static Future<String> get caCertPath => _filePath('ca.crt');
  static Future<String> get caKeyPath => _filePath('ca.key');
  static Future<String> get clientCertPath => _filePath('client.crt');
  static Future<String> get clientKeyPath => _filePath('client.key');
  static Future<String> get serverCertPath => _filePath('server.crt');
  static Future<String> get serverKeyPath => _filePath('server.key');

  // ───── Public API ─────

  /// Returns true if a full certificate set already exists.
  static Future<bool> certificatesExist() async {
    final paths = [
      await caCertPath,
      await caKeyPath,
      await clientCertPath,
      await clientKeyPath,
      await serverCertPath,
      await serverKeyPath,
    ];
    for (final p in paths) {
      if (!await File(p).exists()) return false;
    }
    return true;
  }

  /// Generates the complete CA + client + server certificate set.
  /// Returns true on success.
  static Future<bool> generateCertificates() async {
    try {
      // 1. Generate CA key pair + self-signed CA cert
      final caKeyPair = _generateRSAKeyPair();
      final caPublic = caKeyPair.publicKey as RSAPublicKey;
      final caPrivate = caKeyPair.privateKey as RSAPrivateKey;

      final now = DateTime.now().toUtc();
      final notAfter = now.add(const Duration(days: _validityDays));

      final caCertDer = _buildSelfSignedCert(
        serialNumber: _randomSerial(),
        notBefore: now,
        notAfter: notAfter,
        publicKey: caPublic,
        signingKey: caPrivate,
        cn: 'AI VaultIO Agent CA',
        org: 'AI VaultIO',
        isCA: true,
      );

      // 2. Generate client key pair + CA-signed client cert
      final clientKeyPair = _generateRSAKeyPair();
      final clientPublic = clientKeyPair.publicKey as RSAPublicKey;
      final clientPrivate = clientKeyPair.privateKey as RSAPrivateKey;

      final clientCertDer = _buildSignedCert(
        serialNumber: _randomSerial(),
        notBefore: now,
        notAfter: notAfter,
        subjectPublicKey: clientPublic,
        signingKey: caPrivate,
        issuerCN: 'AI VaultIO Agent CA',
        issuerOrg: 'AI VaultIO',
        subjectCN: 'AI VaultIO Client',
        subjectOrg: 'AI VaultIO',
      );

      // 3. Generate server key pair + CA-signed server cert
      final serverKeyPair = _generateRSAKeyPair();
      final serverPublic = serverKeyPair.publicKey as RSAPublicKey;
      final serverPrivate = serverKeyPair.privateKey as RSAPrivateKey;

      final serverCertDer = _buildSignedCert(
        serialNumber: _randomSerial(),
        notBefore: now,
        notAfter: notAfter,
        subjectPublicKey: serverPublic,
        signingKey: caPrivate,
        issuerCN: 'AI VaultIO Agent CA',
        issuerOrg: 'AI VaultIO',
        subjectCN: 'AI VaultIO Agent Server',
        subjectOrg: 'AI VaultIO',
      );

      // 4. Write all files
      await File(await caCertPath).writeAsString(_toPem(caCertDer, 'CERTIFICATE'));
      await File(await caKeyPath).writeAsString(_toPem(_encodePrivateKey(caPrivate), 'RSA PRIVATE KEY'));
      await File(await clientCertPath).writeAsString(_toPem(clientCertDer, 'CERTIFICATE'));
      await File(await clientKeyPath).writeAsString(_toPem(_encodePrivateKey(clientPrivate), 'RSA PRIVATE KEY'));
      await File(await serverCertPath).writeAsString(_toPem(serverCertDer, 'CERTIFICATE'));
      await File(await serverKeyPath).writeAsString(_toPem(_encodePrivateKey(serverPrivate), 'RSA PRIVATE KEY'));

      // 5. Write metadata
      final metaFile = File(await _filePath('agent_certs.meta'));
      final fingerprint = _sha1Fingerprint(caCertDer);
      await metaFile.writeAsString(
        'ca_fingerprint=$fingerprint\n'
        'generated=${now.toIso8601String()}\n'
        'expires=${notAfter.toIso8601String()}\n',
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns metadata about the generated certificates.
  static Future<Map<String, String>> getCertificateInfo() async {
    try {
      final metaFile = File(await _filePath('agent_certs.meta'));
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

  /// Reads the CA certificate PEM contents.
  static Future<String?> readCaCertPem() async {
    try {
      return await File(await caCertPath).readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Reads the client certificate PEM contents.
  static Future<String?> readClientCertPem() async {
    try {
      return await File(await clientCertPath).readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Reads the client key PEM contents.
  static Future<String?> readClientKeyPem() async {
    try {
      return await File(await clientKeyPath).readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Deletes all generated certificates.
  static Future<void> deleteCertificates() async {
    final dir = await _agentCertsDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Returns the path to the agent_certs directory (for bundling into RPM).
  static Future<String> get certsDirectoryPath async {
    final dir = await _agentCertsDir();
    return dir.path;
  }

  // ───── RSA Key Generation ─────

  static AsymmetricKeyPair<PublicKey, PrivateKey> _generateRSAKeyPair() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), _keyBits, 64),
        secureRandom,
      ));

    return keyGen.generateKeyPair();
  }

  // ───── Certificate Building ─────

  static Uint8List _buildSelfSignedCert({
    required BigInt serialNumber,
    required DateTime notBefore,
    required DateTime notAfter,
    required RSAPublicKey publicKey,
    required RSAPrivateKey signingKey,
    required String cn,
    required String org,
    bool isCA = false,
  }) {
    final name = _buildDistinguishedName(cn, org);
    final extensions = isCA ? _buildCAExtensions() : _buildLeafExtensions();

    final tbsCert = _derSequence([
      _derExplicit(0, _derInteger(BigInt.from(2))), // v3
      _derInteger(serialNumber),
      _buildAlgorithmIdentifier(_oidSha256WithRsa),
      name, // issuer
      _derSequence([_derUtcTime(notBefore), _derUtcTime(notAfter)]),
      name, // subject (same for self-signed)
      _buildSubjectPublicKeyInfo(publicKey),
      extensions,
    ]);

    final signature = _signData(tbsCert, signingKey);
    return _derSequence([
      tbsCert,
      _buildAlgorithmIdentifier(_oidSha256WithRsa),
      _derBitString(signature),
    ]);
  }

  static Uint8List _buildSignedCert({
    required BigInt serialNumber,
    required DateTime notBefore,
    required DateTime notAfter,
    required RSAPublicKey subjectPublicKey,
    required RSAPrivateKey signingKey,
    required String issuerCN,
    required String issuerOrg,
    required String subjectCN,
    required String subjectOrg,
  }) {
    final issuer = _buildDistinguishedName(issuerCN, issuerOrg);
    final subject = _buildDistinguishedName(subjectCN, subjectOrg);

    final tbsCert = _derSequence([
      _derExplicit(0, _derInteger(BigInt.from(2))), // v3
      _derInteger(serialNumber),
      _buildAlgorithmIdentifier(_oidSha256WithRsa),
      issuer,
      _derSequence([_derUtcTime(notBefore), _derUtcTime(notAfter)]),
      subject,
      _buildSubjectPublicKeyInfo(subjectPublicKey),
      _buildLeafExtensions(),
    ]);

    final signature = _signData(tbsCert, signingKey);
    return _derSequence([
      tbsCert,
      _buildAlgorithmIdentifier(_oidSha256WithRsa),
      _derBitString(signature),
    ]);
  }

  // ───── Extensions ─────

  static Uint8List _buildCAExtensions() {
    // Basic Constraints: CA=TRUE
    final basicConstraints = _derSequence([
      _derOid(_oidBasicConstraints),
      _derTag(0x01, Uint8List.fromList([0xFF])), // critical=TRUE
      _derOctetString(_derSequence([
        _derTag(0x01, Uint8List.fromList([0xFF])), // cA=TRUE
      ])),
    ]);

    // Key Usage: keyCertSign, cRLSign
    final keyUsage = _derSequence([
      _derOid(_oidKeyUsage),
      _derTag(0x01, Uint8List.fromList([0xFF])), // critical=TRUE
      _derOctetString(_derBitString(Uint8List.fromList([0x06]))), // keyCertSign + cRLSign
    ]);

    return _derExplicit(3, _derSequence([basicConstraints, keyUsage]));
  }

  static Uint8List _buildLeafExtensions() {
    // Basic Constraints: CA=FALSE
    final basicConstraints = _derSequence([
      _derOid(_oidBasicConstraints),
      _derOctetString(_derSequence([])), // empty = CA false
    ]);

    return _derExplicit(3, _derSequence([basicConstraints]));
  }

  // ───── ASN.1 DER Encoding ─────

  static final _oidSha256WithRsa = [1, 2, 840, 113549, 1, 1, 11];
  static final _oidRsaEncryption = [1, 2, 840, 113549, 1, 1, 1];
  static final _oidCommonName = [2, 5, 4, 3];
  static final _oidOrganization = [2, 5, 4, 10];
  static final _oidBasicConstraints = [2, 5, 29, 19];
  static final _oidKeyUsage = [2, 5, 29, 15];

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
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    return _derTag(0x02, bytes);
  }

  static Uint8List _derOid(List<int> oid) {
    final encoded = <int>[oid[0] * 40 + oid[1]];
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

  static Uint8List _derBitString(Uint8List data) =>
      _derTag(0x03, Uint8List.fromList([0, ...data]));

  static Uint8List _derOctetString(Uint8List data) => _derTag(0x04, data);

  static Uint8List _derUtf8String(String s) =>
      _derTag(0x0C, Uint8List.fromList(s.codeUnits));

  static Uint8List _derPrintableString(String s) =>
      _derTag(0x13, Uint8List.fromList(s.codeUnits));

  static Uint8List _derUtcTime(DateTime dt) {
    final utc = dt.toUtc();
    final s = '${_pad2(utc.year % 100)}${_pad2(utc.month)}${_pad2(utc.day)}'
        '${_pad2(utc.hour)}${_pad2(utc.minute)}${_pad2(utc.second)}Z';
    return _derTag(0x17, Uint8List.fromList(s.codeUnits));
  }

  static Uint8List _derExplicit(int tagNumber, Uint8List content) =>
      _derTag(0xA0 | tagNumber, content);

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  static Uint8List _buildAlgorithmIdentifier(List<int> oid) {
    return _derSequence([
      _derOid(oid),
      Uint8List.fromList([0x05, 0x00]),
    ]);
  }

  static Uint8List _buildDistinguishedName(String cn, String org) {
    return _derSequence([
      _derSet([
        _derSequence([_derOid(_oidCommonName), _derUtf8String(cn)]),
      ]),
      _derSet([
        _derSequence([_derOid(_oidOrganization), _derPrintableString(org)]),
      ]),
    ]);
  }

  static Uint8List _buildSubjectPublicKeyInfo(RSAPublicKey publicKey) {
    final rsaPubKey = _derSequence([
      _derInteger(publicKey.modulus!),
      _derInteger(publicKey.publicExponent!),
    ]);
    return _derSequence([
      _buildAlgorithmIdentifier(_oidRsaEncryption),
      _derBitString(rsaPubKey),
    ]);
  }

  static Uint8List _encodePrivateKey(RSAPrivateKey key) {
    return _derSequence([
      _derInteger(BigInt.zero),
      _derInteger(key.modulus!),
      _derInteger(key.publicExponent!),
      _derInteger(key.privateExponent!),
      _derInteger(key.p!),
      _derInteger(key.q!),
      _derInteger(key.privateExponent! % (key.p! - BigInt.one)),
      _derInteger(key.privateExponent! % (key.q! - BigInt.one)),
      _derInteger(key.q!.modInverse(key.p!)),
    ]);
  }

  static Uint8List _signData(Uint8List data, RSAPrivateKey privateKey) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final sig = signer.generateSignature(data);
    return sig.bytes;
  }

  static BigInt _randomSerial() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[0] &= 0x7F;
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
    lines.add('');
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
