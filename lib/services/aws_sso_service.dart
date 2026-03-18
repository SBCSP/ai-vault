import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Represents an AWS account visible via SSO.
class AwsAccount {
  final String accountId;
  final String accountName;
  final String emailAddress;

  const AwsAccount({
    required this.accountId,
    required this.accountName,
    required this.emailAddress,
  });
}

/// Represents an IAM role available in an AWS account via SSO.
class AwsAccountRole {
  final String roleName;
  final String accountId;

  const AwsAccountRole({
    required this.roleName,
    required this.accountId,
  });
}

/// Temporary AWS credentials obtained via SSO.
class AwsCredentials {
  final String accessKeyId;
  final String secretAccessKey;
  final String sessionToken;
  final DateTime expiration;

  const AwsCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    required this.expiration,
  });

  bool get isExpired => DateTime.now().isAfter(expiration);
}

/// Handles AWS SSO OIDC device authorization flow.
///
/// Flow:
/// 1. RegisterClient → clientId + clientSecret
/// 2. StartDeviceAuthorization → verificationUri + deviceCode + userCode
/// 3. User opens browser and authenticates
/// 4. CreateToken (poll) → accessToken
/// 5. ListAccounts → available AWS accounts
/// 6. ListAccountRoles → roles in chosen account
/// 7. GetRoleCredentials → temporary AWS credentials
class AwsSsoService {
  final String ssoStartUrl;
  final String region;
  final http.Client _client;

  String? _clientId;
  String? _clientSecret;
  String? _accessToken;
  DateTime? _tokenExpiresAt;

  AwsSsoService({
    required this.ssoStartUrl,
    required this.region,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get _oidcEndpoint => 'https://oidc.$region.amazonaws.com';
  String get _ssoEndpoint => 'https://portal.sso.$region.amazonaws.com';

  bool get hasValidToken =>
      _accessToken != null &&
      _tokenExpiresAt != null &&
      DateTime.now().isBefore(_tokenExpiresAt!);

  String? get accessToken => _accessToken;

  /// Restore a previously saved token.
  void restoreToken(String token, DateTime expiresAt) {
    _accessToken = token;
    _tokenExpiresAt = expiresAt;
  }

  /// Step 1: Register this app as an OIDC client.
  Future<void> _registerClient() async {
    final response = await _client.post(
      Uri.parse('$_oidcEndpoint/client/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'clientName': 'AI VaultIO',
        'clientType': 'public',
      }),
    );

    if (response.statusCode != 200) {
      throw AwsSsoException(
        'Failed to register OIDC client: ${response.statusCode}',
        response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _clientId = data['clientId'] as String;
    _clientSecret = data['clientSecret'] as String;
  }

  /// Step 2 & 3: Start device authorization and open browser.
  /// Returns a Future that completes when the user has authenticated.
  ///
  /// [onBrowserOpened] is called with the user code after the browser is launched.
  Future<void> authenticate({
    void Function(String userCode)? onBrowserOpened,
    void Function(String status)? onStatusChanged,
  }) async {
    onStatusChanged?.call('Registering client...');
    await _registerClient();

    onStatusChanged?.call('Starting device authorization...');
    final authResponse = await _client.post(
      Uri.parse('$_oidcEndpoint/device_authorization'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'clientId': _clientId,
        'clientSecret': _clientSecret,
        'startUrl': ssoStartUrl,
      }),
    );

    if (authResponse.statusCode != 200) {
      throw AwsSsoException(
        'Failed to start device authorization: ${authResponse.statusCode}',
        authResponse.body,
      );
    }

    final authData = jsonDecode(authResponse.body) as Map<String, dynamic>;
    final deviceCode = authData['deviceCode'] as String;
    final userCode = authData['userCode'] as String;
    final verificationUri = authData['verificationUri'] as String;
    final verificationUriComplete =
        authData['verificationUriComplete'] as String?;
    final interval = (authData['interval'] as int?) ?? 5;
    final expiresIn = (authData['expiresIn'] as int?) ?? 600;

    // Open browser for user authentication
    final uriToOpen =
        Uri.parse(verificationUriComplete ?? verificationUri);
    onStatusChanged?.call('Opening browser for authentication...');

    if (await canLaunchUrl(uriToOpen)) {
      await launchUrl(uriToOpen, mode: LaunchMode.externalApplication);
    } else {
      throw AwsSsoException(
        'Could not open browser',
        'Please open this URL manually: $uriToOpen\nUser code: $userCode',
      );
    }

    onBrowserOpened?.call(userCode);
    onStatusChanged?.call('Waiting for authentication...');

    // Step 4: Poll for token
    final deadline = DateTime.now().add(Duration(seconds: expiresIn));

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(Duration(seconds: interval));

      final tokenResponse = await _client.post(
        Uri.parse('$_oidcEndpoint/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'clientId': _clientId,
          'clientSecret': _clientSecret,
          'deviceCode': deviceCode,
          'grantType': 'urn:ietf:params:oauth:grant-type:device_code',
        }),
      );

      if (tokenResponse.statusCode == 200) {
        final tokenData =
            jsonDecode(tokenResponse.body) as Map<String, dynamic>;
        _accessToken = tokenData['accessToken'] as String;
        final expiresIn = tokenData['expiresIn'] as int;
        _tokenExpiresAt =
            DateTime.now().add(Duration(seconds: expiresIn));
        onStatusChanged?.call('Authenticated successfully!');
        return;
      }

      final errorBody =
          jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final error = errorBody['error'] as String?;

      if (error == 'authorization_pending') {
        continue; // Keep polling
      } else if (error == 'slow_down') {
        await Future.delayed(const Duration(seconds: 5)); // Extra delay
        continue;
      } else if (error == 'expired_token') {
        throw AwsSsoException(
          'Authentication timed out',
          'The device authorization has expired. Please try again.',
        );
      } else {
        throw AwsSsoException(
          'Authentication failed',
          errorBody['error_description'] as String? ?? error ?? 'Unknown error',
        );
      }
    }

    throw AwsSsoException(
      'Authentication timed out',
      'Did not receive authorization within the time limit.',
    );
  }

  /// Step 5: List AWS accounts available via SSO.
  Future<List<AwsAccount>> listAccounts() async {
    if (!hasValidToken) {
      throw AwsSsoException('Not authenticated', 'Please connect first.');
    }

    final accounts = <AwsAccount>[];
    String? nextToken;

    do {
      final queryParams = <String, String>{
        if (nextToken != null) 'next_token': nextToken,
        'max_result': '100',
      };

      final uri = Uri.parse('$_ssoEndpoint/assignment/accounts')
          .replace(queryParameters: queryParams);

      final response = await _client.get(uri, headers: {
        'x-amz-sso_bearer_token': _accessToken!,
        'Content-Type': 'application/json',
      });

      if (response.statusCode != 200) {
        throw AwsSsoException(
          'Failed to list accounts: ${response.statusCode}',
          response.body,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final accountList = data['accountList'] as List<dynamic>? ?? [];

      for (final acct in accountList) {
        final a = acct as Map<String, dynamic>;
        accounts.add(AwsAccount(
          accountId: a['accountId'] as String,
          accountName: a['accountName'] as String? ?? '',
          emailAddress: a['emailAddress'] as String? ?? '',
        ));
      }

      nextToken = data['nextToken'] as String?;
    } while (nextToken != null);

    return accounts;
  }

  /// Step 6: List roles available in an account.
  Future<List<AwsAccountRole>> listAccountRoles(String accountId) async {
    if (!hasValidToken) {
      throw AwsSsoException('Not authenticated', 'Please connect first.');
    }

    final roles = <AwsAccountRole>[];
    String? nextToken;

    do {
      final queryParams = <String, String>{
        'account_id': accountId,
        if (nextToken != null) 'next_token': nextToken,
      };

      final uri = Uri.parse('$_ssoEndpoint/assignment/roles')
          .replace(queryParameters: queryParams);

      final response = await _client.get(uri, headers: {
        'x-amz-sso_bearer_token': _accessToken!,
        'Content-Type': 'application/json',
      });

      if (response.statusCode != 200) {
        throw AwsSsoException(
          'Failed to list roles: ${response.statusCode}',
          response.body,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final roleList = data['roleList'] as List<dynamic>? ?? [];

      for (final role in roleList) {
        final r = role as Map<String, dynamic>;
        roles.add(AwsAccountRole(
          roleName: r['roleName'] as String,
          accountId: accountId,
        ));
      }

      nextToken = data['nextToken'] as String?;
    } while (nextToken != null);

    return roles;
  }

  /// Step 7: Get temporary AWS credentials for a role.
  Future<AwsCredentials> getRoleCredentials({
    required String accountId,
    required String roleName,
  }) async {
    if (!hasValidToken) {
      throw AwsSsoException('Not authenticated', 'Please connect first.');
    }

    final uri = Uri.parse('$_ssoEndpoint/federation/credentials').replace(
      queryParameters: {
        'account_id': accountId,
        'role_name': roleName,
      },
    );

    final response = await _client.get(uri, headers: {
      'x-amz-sso_bearer_token': _accessToken!,
      'Content-Type': 'application/json',
    });

    if (response.statusCode != 200) {
      throw AwsSsoException(
        'Failed to get credentials: ${response.statusCode}',
        response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final creds = data['roleCredentials'] as Map<String, dynamic>;

    return AwsCredentials(
      accessKeyId: creds['accessKeyId'] as String,
      secretAccessKey: creds['secretAccessKey'] as String,
      sessionToken: creds['sessionToken'] as String,
      expiration: DateTime.fromMillisecondsSinceEpoch(
        creds['expiration'] as int,
      ),
    );
  }

  /// Disconnect: clear tokens.
  void disconnect() {
    _accessToken = null;
    _tokenExpiresAt = null;
    _clientId = null;
    _clientSecret = null;
  }

  void dispose() {
    _client.close();
  }
}

class AwsSsoException implements Exception {
  final String message;
  final String details;

  const AwsSsoException(this.message, this.details);

  @override
  String toString() => 'AwsSsoException: $message — $details';
}
