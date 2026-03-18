import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'aws_sso_service.dart';

/// A secret retrieved from AWS Secrets Manager.
class AwsSecret {
  final String name;
  final String arn;
  final String? description;
  final String? secretString;
  final List<String> tags;
  final DateTime? lastChangedDate;

  const AwsSecret({
    required this.name,
    required this.arn,
    this.description,
    this.secretString,
    this.tags = const [],
    this.lastChangedDate,
  });
}

/// Calls AWS Secrets Manager APIs using SigV4 signed requests.
class AwsSecretsManagerService {
  final String region;
  final http.Client _client;

  AwsSecretsManagerService({
    required this.region,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get _endpoint => 'https://secretsmanager.$region.amazonaws.com';

  /// List all secrets (metadata only, not values).
  Future<List<AwsSecret>> listSecrets(AwsCredentials credentials) async {
    final secrets = <AwsSecret>[];
    String? nextToken;

    do {
      final body = <String, dynamic>{
        'MaxResults': 100,
        if (nextToken != null) 'NextToken': nextToken,
      };

      final response = await _signedRequest(
        credentials: credentials,
        target: 'secretsmanager.ListSecrets',
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw AwsSecretsManagerException(
          'Failed to list secrets: ${response.statusCode}',
          response.body,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final secretList = data['SecretList'] as List<dynamic>? ?? [];

      for (final s in secretList) {
        final secret = s as Map<String, dynamic>;
        final awsTags = secret['Tags'] as List<dynamic>? ?? [];
        secrets.add(AwsSecret(
          name: secret['Name'] as String,
          arn: secret['ARN'] as String,
          description: secret['Description'] as String?,
          tags: awsTags
              .map((t) =>
                  '${(t as Map<String, dynamic>)['Key']}:${t['Value']}')
              .toList(),
          lastChangedDate: secret['LastChangedDate'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  ((secret['LastChangedDate'] as num) * 1000).toInt())
              : null,
        ));
      }

      nextToken = data['NextToken'] as String?;
    } while (nextToken != null);

    return secrets;
  }

  /// Get the actual secret value for a specific secret.
  Future<AwsSecret> getSecretValue(
    AwsCredentials credentials,
    AwsSecret secretMeta,
  ) async {
    final body = jsonEncode({'SecretId': secretMeta.arn});

    final response = await _signedRequest(
      credentials: credentials,
      target: 'secretsmanager.GetSecretValue',
      body: body,
    );

    if (response.statusCode != 200) {
      throw AwsSecretsManagerException(
        'Failed to get secret value for ${secretMeta.name}: ${response.statusCode}',
        response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    return AwsSecret(
      name: secretMeta.name,
      arn: secretMeta.arn,
      description: secretMeta.description,
      secretString: data['SecretString'] as String?,
      tags: secretMeta.tags,
      lastChangedDate: secretMeta.lastChangedDate,
    );
  }

  /// Make a SigV4-signed POST request to Secrets Manager.
  Future<http.Response> _signedRequest({
    required AwsCredentials credentials,
    required String target,
    required String body,
  }) async {
    final uri = Uri.parse(_endpoint);
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDate(now);
    final amzDate = _formatAmzDate(now);
    final service = 'secretsmanager';

    // Headers that will be signed
    final headers = <String, String>{
      'Content-Type': 'application/x-amz-json-1.1',
      'Host': uri.host,
      'X-Amz-Date': amzDate,
      'X-Amz-Target': target,
      'X-Amz-Security-Token': credentials.sessionToken,
    };

    // Step 1: Create canonical request
    final payloadHash = _sha256Hex(body);

    final signedHeaders = (headers.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
        .map((k) => k.toLowerCase())
        .toList();
    final signedHeadersStr = signedHeaders.join(';');

    final canonicalHeaders = signedHeaders
        .map((h) => '$h:${headers[headers.keys.firstWhere((k) => k.toLowerCase() == h)]!.trim()}')
        .join('\n');

    final canonicalRequest = [
      'POST',
      uri.path.isEmpty ? '/' : uri.path,
      '', // query string (empty)
      '$canonicalHeaders\n',
      signedHeadersStr,
      payloadHash,
    ].join('\n');

    // Step 2: Create string to sign
    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      _sha256Hex(canonicalRequest),
    ].join('\n');

    // Step 3: Calculate signing key
    final signingKey = _getSignatureKey(
      credentials.secretAccessKey,
      dateStamp,
      region,
      service,
    );

    // Step 4: Calculate signature
    final signature = _hmacSha256Hex(signingKey, stringToSign);

    // Step 5: Build authorization header
    final authorization =
        'AWS4-HMAC-SHA256 Credential=${credentials.accessKeyId}/$credentialScope, '
        'SignedHeaders=$signedHeadersStr, '
        'Signature=$signature';

    headers['Authorization'] = authorization;

    return _client.post(uri, headers: headers, body: body);
  }

  // --- SigV4 helper methods ---

  String _formatDate(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

  String _formatAmzDate(DateTime dt) =>
      '${_formatDate(dt)}T${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}${dt.second.toString().padLeft(2, '0')}Z';

  String _sha256Hex(String data) {
    final bytes = utf8.encode(data);
    return sha256.convert(bytes).toString();
  }

  List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }

  String _hmacSha256Hex(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).toString();
  }

  List<int> _getSignatureKey(
    String secretKey,
    String dateStamp,
    String regionName,
    String serviceName,
  ) {
    final kDate = _hmacSha256(utf8.encode('AWS4$secretKey'), dateStamp);
    final kRegion = _hmacSha256(kDate, regionName);
    final kService = _hmacSha256(kRegion, serviceName);
    final kSigning = _hmacSha256(kService, 'aws4_request');
    return kSigning;
  }

  void dispose() {
    _client.close();
  }
}

class AwsSecretsManagerException implements Exception {
  final String message;
  final String details;

  const AwsSecretsManagerException(this.message, this.details);

  @override
  String toString() => 'AwsSecretsManagerException: $message — $details';
}
