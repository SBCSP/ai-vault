import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/linear_models.dart';

/// Fixed port for the OAuth localhost callback server.
const _kCallbackPort = 9874;

/// Linear OAuth 2.0 + GraphQL API service.
///
/// OAuth flow (Authorization Code):
/// 1. Start local HTTP callback server on port [_kCallbackPort]
/// 2. Open browser at Linear authorize URL
/// 3. User approves → Linear redirects to http://localhost:[_kCallbackPort]/callback
/// 4. Extract authorization code from redirect
/// 5. Exchange code for access token
/// 6. Store token; use it for all API calls
class LinearService {
  static const _authBaseUrl = 'https://linear.app/oauth/authorize';
  static const _tokenUrl = 'https://api.linear.app/oauth/token';
  static const _graphqlUrl = 'https://api.linear.app/graphql';
  static const _redirectUri = 'http://localhost:$_kCallbackPort/callback';

  final http.Client _client;

  String? _accessToken;

  LinearService({http.Client? client}) : _client = client ?? http.Client();

  bool get isAuthenticated => _accessToken != null;

  /// Set a previously stored token to restore authenticated state.
  void restoreToken(String token) {
    _accessToken = token;
  }

  /// Clear token on disconnect.
  void clearToken() {
    _accessToken = null;
  }

  // ---------------------------------------------------------------------------
  // OAuth Authorization Code Flow
  // ---------------------------------------------------------------------------

  /// Run the OAuth Authorization Code flow.
  ///
  /// Starts a local HTTP server, opens the browser, waits for the redirect,
  /// then exchanges the code for a token.
  ///
  /// Returns the access token string on success.
  Future<String> authenticate({
    required String clientId,
    required String clientSecret,
    void Function(String status)? onStatusChanged,
  }) async {
    onStatusChanged?.call('Starting local callback server...');

    // Start callback server
    HttpServer server;
    try {
      server = await HttpServer.bind('127.0.0.1', _kCallbackPort);
    } on SocketException {
      throw LinearException(
        'Port $_kCallbackPort is in use',
        'Another process is using port $_kCallbackPort. '
            'Please close it and try again.',
      );
    }

    try {
      final state = _generateState();

      final authUri = Uri.parse(_authBaseUrl).replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': _redirectUri,
          'response_type': 'code',
          'scope': 'read,write',
          'state': state,
          'actor': 'user',
        },
      );

      onStatusChanged?.call('Opening browser...');
      if (!await launchUrl(authUri, mode: LaunchMode.externalApplication)) {
        throw LinearException(
          'Could not open browser',
          'Please open this URL manually: $authUri',
        );
      }

      onStatusChanged?.call('Waiting for authorization...');
      final code = await _waitForCallback(server, state)
          .timeout(const Duration(minutes: 5), onTimeout: () {
        throw LinearException(
          'Authentication timed out',
          'Did not receive authorization within 5 minutes.',
        );
      });

      onStatusChanged?.call('Exchanging code for token...');
      final token = await _exchangeCode(
        code: code,
        clientId: clientId,
        clientSecret: clientSecret,
      );

      _accessToken = token;
      onStatusChanged?.call('Connected!');
      return token;
    } finally {
      await server.close(force: true);
    }
  }

  /// Wait for the OAuth callback on the local server.
  Future<String> _waitForCallback(HttpServer server, String expectedState) async {
    await for (final request in server) {
      if (request.uri.path == '/callback') {
        final code = request.uri.queryParameters['code'];
        final returnedState = request.uri.queryParameters['state'];
        final error = request.uri.queryParameters['error'];

        // Send HTML response to the browser
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('''<!DOCTYPE html>
<html>
<head><title>AI VaultIO — Authorization</title>
<style>
  body { font-family: -apple-system, sans-serif; display: flex; align-items: center;
         justify-content: center; height: 100vh; margin: 0; background: #f5f5f5; }
  .card { background: white; padding: 32px 40px; border-radius: 12px;
          box-shadow: 0 2px 16px rgba(0,0,0,0.1); text-align: center; max-width: 400px; }
  h1 { color: #5e6ad2; margin-bottom: 8px; }
  p { color: #666; }
</style></head>
<body><div class="card">
  <h1>${error != null ? 'Authorization Failed' : 'Authorization Successful!'}</h1>
  <p>${error != null ? 'Error: $error. You can close this window.' : 'You can close this window and return to AI VaultIO.'}</p>
</div></body></html>''');
        await request.response.close();

        if (error != null) {
          throw LinearException(
            'Authorization denied',
            error,
          );
        }
        if (returnedState != expectedState) {
          throw LinearException(
            'State mismatch',
            'Possible CSRF attack detected. Please try again.',
          );
        }
        if (code == null) {
          throw LinearException(
            'No authorization code',
            'Linear did not return an authorization code.',
          );
        }
        return code;
      } else {
        // 404 for anything else
        request.response
          ..statusCode = 404
          ..write('Not found');
        await request.response.close();
      }
    }
    throw LinearException('Callback server closed', 'No callback received.');
  }

  /// Exchange authorization code for access token.
  Future<String> _exchangeCode({
    required String code,
    required String clientId,
    required String clientSecret,
  }) async {
    final response = await _client.post(
      Uri.parse(_tokenUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: {
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': _redirectUri,
        'grant_type': 'authorization_code',
      },
    );

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw LinearException(
        'Token exchange failed (${response.statusCode})',
        (body['error_description'] as String?) ??
            (body['error'] as String?) ??
            response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    if (token == null) {
      throw LinearException(
        'No access token in response',
        response.body,
      );
    }
    return token;
  }

  String _generateState() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  // ---------------------------------------------------------------------------
  // GraphQL Helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _query(
    String queryStr, {
    Map<String, dynamic>? variables,
  }) async {
    if (_accessToken == null) {
      throw LinearException('Not authenticated', 'Please connect to Linear first.');
    }

    final response = await _client.post(
      Uri.parse(_graphqlUrl),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'query': queryStr,
        if (variables != null) 'variables': variables,
      }),
    );

    if (response.statusCode == 401) {
      throw LinearException(
        'Unauthorized',
        'Your Linear token has been revoked or is invalid. Please reconnect.',
      );
    }

    if (response.statusCode != 200) {
      throw LinearException(
        'API request failed (${response.statusCode})',
        response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final errors = data['errors'] as List<dynamic>?;
    if (errors != null && errors.isNotEmpty) {
      final msg = (errors.first as Map<String, dynamic>)['message'] as String?;
      throw LinearException('GraphQL error', msg ?? 'Unknown error');
    }

    return data['data'] as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // API Methods
  // ---------------------------------------------------------------------------

  static const _viewerQuery = '''
query Viewer {
  viewer {
    id
    name
    email
    organization {
      id
      name
      urlKey
    }
  }
}
''';

  Future<LinearViewer> getViewer() async {
    final data = await _query(_viewerQuery);
    return LinearViewer.fromJson(data['viewer'] as Map<String, dynamic>);
  }

  static const _teamsQuery = '''
query Teams {
  teams(first: 50) {
    nodes {
      id
      name
      key
      states {
        nodes {
          id
          name
          color
          type
        }
      }
    }
  }
}
''';

  Future<List<LinearTeam>> getTeams() async {
    final data = await _query(_teamsQuery);
    final nodes =
        (data['teams'] as Map<String, dynamic>)['nodes'] as List<dynamic>;
    return nodes
        .map((n) => LinearTeam.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  static const _projectsQuery = '''
query Projects {
  projects(first: 100) {
    nodes {
      id
      name
      state
      color
    }
  }
}
''';

  Future<List<LinearProject>> getProjects() async {
    final data = await _query(_projectsQuery);
    final nodes =
        (data['projects'] as Map<String, dynamic>)['nodes'] as List<dynamic>;
    return nodes
        .map((n) => LinearProject.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  static const _issuesQuery = '''
query Issues(\$after: String, \$filter: IssueFilter) {
  issues(first: 100, after: \$after, filter: \$filter, orderBy: updatedAt) {
    nodes {
      id
      identifier
      title
      description
      priority
      url
      createdAt
      updatedAt
      dueDate
      state {
        id
        name
        color
        type
      }
      assignee {
        id
        name
        email
      }
      team {
        id
        name
        key
      }
      project {
        id
        name
        color
        state
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
''';

  /// Fetch all issues, paginating automatically.
  ///
  /// If [teamIds] is provided, only fetches issues from those teams.
  /// If [onlyMine] is true, only fetches issues assigned to the current user.
  Future<List<LinearIssue>> getIssues({
    List<String>? teamIds,
    bool onlyMine = false,
  }) async {
    final issues = <LinearIssue>[];
    String? cursor;
    bool hasNextPage = true;

    // Build filter
    Map<String, dynamic>? filter;
    final filterParts = <String, dynamic>{};
    if (teamIds != null && teamIds.isNotEmpty) {
      filterParts['team'] = {
        'id': {'in': teamIds}
      };
    }
    if (onlyMine) {
      filterParts['assignee'] = {
        'isMe': {'eq': true}
      };
    }
    if (filterParts.isNotEmpty) filter = filterParts;

    while (hasNextPage) {
      final data = await _query(
        _issuesQuery,
        variables: {
          if (cursor != null) 'after': cursor,
          if (filter != null) 'filter': filter,
        },
      );

      final issuesData = data['issues'] as Map<String, dynamic>;
      final nodes = issuesData['nodes'] as List<dynamic>;
      final pageInfo = issuesData['pageInfo'] as Map<String, dynamic>;

      for (final n in nodes) {
        try {
          issues.add(LinearIssue.fromJson(n as Map<String, dynamic>));
        } catch (_) {
          // Skip malformed issues
        }
      }

      hasNextPage = pageInfo['hasNextPage'] as bool? ?? false;
      cursor = pageInfo['endCursor'] as String?;

      // Safety limit — don't fetch more than 500 issues
      if (issues.length >= 500) break;
    }

    return issues;
  }

  static const _createIssueMutation = '''
mutation CreateIssue(\$input: IssueCreateInput!) {
  issueCreate(input: \$input) {
    success
    issue {
      id
      identifier
      title
      description
      priority
      url
      createdAt
      updatedAt
      dueDate
      state {
        id
        name
        color
        type
      }
      assignee {
        id
        name
        email
      }
      team {
        id
        name
        key
      }
      project {
        id
        name
        color
        state
      }
    }
  }
}
''';

  Future<LinearIssue> createIssue({
    required String teamId,
    required String title,
    String? description,
    String? stateId,
    int priority = 0,
    String? assigneeId,
    String? projectId,
    DateTime? dueDate,
  }) async {
    final input = <String, dynamic>{
      'teamId': teamId,
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (stateId != null) 'stateId': stateId,
      'priority': priority,
      if (assigneeId != null) 'assigneeId': assigneeId,
      if (projectId != null) 'projectId': projectId,
      if (dueDate != null)
        'dueDate':
            '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}',
    };

    final data = await _query(_createIssueMutation, variables: {'input': input});
    final result = data['issueCreate'] as Map<String, dynamic>;
    final success = result['success'] as bool? ?? false;
    if (!success) {
      throw LinearException('Failed to create issue', 'API returned success=false');
    }
    return LinearIssue.fromJson(result['issue'] as Map<String, dynamic>);
  }

  static const _updateIssueStateMutation = '''
mutation UpdateIssueState(\$id: String!, \$stateId: String!) {
  issueUpdate(id: \$id, input: { stateId: \$stateId }) {
    success
    issue {
      id
      identifier
      title
      description
      priority
      url
      createdAt
      updatedAt
      dueDate
      state {
        id
        name
        color
        type
      }
      assignee {
        id
        name
        email
      }
      team {
        id
        name
        key
      }
      project {
        id
        name
        color
        state
      }
    }
  }
}
''';

  Future<LinearIssue> updateIssueState({
    required String issueId,
    required String stateId,
  }) async {
    final data = await _query(
      _updateIssueStateMutation,
      variables: {'id': issueId, 'stateId': stateId},
    );
    final result = data['issueUpdate'] as Map<String, dynamic>;
    return LinearIssue.fromJson(result['issue'] as Map<String, dynamic>);
  }

  void dispose() {
    _client.close();
  }
}

/// Exception thrown by [LinearService].
class LinearException implements Exception {
  final String message;
  final String details;

  const LinearException(this.message, this.details);

  @override
  String toString() => 'LinearException: $message — $details';
}
