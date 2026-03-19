import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vault_entry.dart';
import '../services/aws_secrets_manager_service.dart';
import '../services/aws_sso_service.dart';
import 'audit_provider.dart';
import 'embedding_provider.dart';
import 'vault_provider.dart';

/// Status of the AWS SSO connection.
enum AwsConnectionStatus {
  disconnected,
  connecting,
  authenticated,
  syncing,
  error,
}

/// Result of a sync operation.
class AwsSyncResult {
  final int created;
  final int updated;
  final int failed;
  final int total;
  final String? error;

  const AwsSyncResult({
    this.created = 0,
    this.updated = 0,
    this.failed = 0,
    this.total = 0,
    this.error,
  });

  String get summary {
    if (error != null) return 'Sync failed: $error';
    final parts = <String>[];
    if (created > 0) parts.add('$created created');
    if (updated > 0) parts.add('$updated updated');
    if (failed > 0) parts.add('$failed failed');
    if (parts.isEmpty) return 'No secrets to sync';
    return parts.join(' \u2022 ');
  }
}

/// Full state for AWS integration.
class AwsState {
  final String ssoStartUrl;
  final String region;
  final AwsConnectionStatus status;
  final String? statusMessage;
  final String? userCode;
  final String? error;

  // After authentication
  final List<AwsAccount> accounts;
  final String? selectedAccountId;
  final List<AwsAccountRole> roles;
  final String? selectedRoleName;

  // Sync state
  final DateTime? lastSyncAt;
  final AwsSyncResult? lastSyncResult;

  const AwsState({
    this.ssoStartUrl = '',
    this.region = 'us-east-1',
    this.status = AwsConnectionStatus.disconnected,
    this.statusMessage,
    this.userCode,
    this.error,
    this.accounts = const [],
    this.selectedAccountId,
    this.roles = const [],
    this.selectedRoleName,
    this.lastSyncAt,
    this.lastSyncResult,
  });

  AwsState copyWith({
    String? ssoStartUrl,
    String? region,
    AwsConnectionStatus? status,
    String? statusMessage,
    String? userCode,
    String? error,
    List<AwsAccount>? accounts,
    String? selectedAccountId,
    List<AwsAccountRole>? roles,
    String? selectedRoleName,
    DateTime? lastSyncAt,
    AwsSyncResult? lastSyncResult,
    bool clearError = false,
    bool clearUserCode = false,
    bool clearStatusMessage = false,
  }) {
    return AwsState(
      ssoStartUrl: ssoStartUrl ?? this.ssoStartUrl,
      region: region ?? this.region,
      status: status ?? this.status,
      statusMessage:
          clearStatusMessage ? null : (statusMessage ?? this.statusMessage),
      userCode: clearUserCode ? null : (userCode ?? this.userCode),
      error: clearError ? null : (error ?? this.error),
      accounts: accounts ?? this.accounts,
      selectedAccountId: selectedAccountId ?? this.selectedAccountId,
      roles: roles ?? this.roles,
      selectedRoleName: selectedRoleName ?? this.selectedRoleName,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastSyncResult: lastSyncResult ?? this.lastSyncResult,
    );
  }
}

/// AWS regions commonly used.
const awsRegions = [
  'us-east-1',
  'us-east-2',
  'us-west-1',
  'us-west-2',
  'eu-west-1',
  'eu-west-2',
  'eu-west-3',
  'eu-central-1',
  'eu-north-1',
  'ap-southeast-1',
  'ap-southeast-2',
  'ap-northeast-1',
  'ap-northeast-2',
  'ap-south-1',
  'ca-central-1',
  'sa-east-1',
];

final awsProvider =
    StateNotifierProvider<AwsNotifier, AwsState>((ref) {
  return AwsNotifier(ref);
});

class AwsNotifier extends StateNotifier<AwsState> {
  final Ref _ref;
  AwsSsoService? _ssoService;

  AwsNotifier(this._ref) : super(const AwsState()) {
    _loadConfig();
  }

  /// Load saved SSO configuration from prefs.
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('aws_sso_start_url') ?? '';
    final region = prefs.getString('aws_sso_region') ?? 'us-east-1';

    state = state.copyWith(
      ssoStartUrl: url,
      region: region,
    );
  }

  /// Save SSO configuration.
  Future<void> setSsoConfig(String startUrl, String region) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aws_sso_start_url', startUrl);
    await prefs.setString('aws_sso_region', region);

    // Reset connection when config changes
    _ssoService?.disconnect();
    _ssoService = null;

    state = AwsState(
      ssoStartUrl: startUrl,
      region: region,
    );
  }

  /// Initiate SSO device authorization flow.
  Future<void> connect() async {
    if (state.ssoStartUrl.isEmpty) {
      state = state.copyWith(
        error: 'Please enter your AWS SSO Start URL first.',
        status: AwsConnectionStatus.error,
      );
      return;
    }

    state = state.copyWith(
      status: AwsConnectionStatus.connecting,
      clearError: true,
      clearUserCode: true,
    );

    _ssoService = AwsSsoService(
      ssoStartUrl: state.ssoStartUrl,
      region: state.region,
    );

    try {
      await _ssoService!.authenticate(
        onBrowserOpened: (userCode) {
          state = state.copyWith(userCode: userCode);
        },
        onStatusChanged: (status) {
          state = state.copyWith(statusMessage: status);
        },
      );

      // Authenticated — fetch accounts
      state = state.copyWith(
        status: AwsConnectionStatus.authenticated,
        statusMessage: 'Loading accounts...',
        clearUserCode: true,
      );

      final accounts = await _ssoService!.listAccounts();

      state = state.copyWith(
        accounts: accounts,
        statusMessage: '${accounts.length} account(s) found',
      );

      await _ref.read(auditLoggerProvider).log(
        action: AuditAction.awsConnected,
        details: '${accounts.length} account(s) found',
      );

      // Auto-select if only one account
      if (accounts.length == 1) {
        await selectAccount(accounts.first.accountId);
      }
    } on AwsSsoException catch (e) {
      state = state.copyWith(
        status: AwsConnectionStatus.error,
        error: '${e.message}\n${e.details}',
        clearUserCode: true,
        clearStatusMessage: true,
      );
    } catch (e) {
      state = state.copyWith(
        status: AwsConnectionStatus.error,
        error: e.toString(),
        clearUserCode: true,
        clearStatusMessage: true,
      );
    }
  }

  /// Select an account and load its roles.
  Future<void> selectAccount(String accountId) async {
    state = state.copyWith(
      selectedAccountId: accountId,
      statusMessage: 'Loading roles...',
    );

    try {
      final roles = await _ssoService!.listAccountRoles(accountId);

      state = state.copyWith(
        roles: roles,
        statusMessage: '${roles.length} role(s) available',
      );

      // Auto-select if only one role
      if (roles.length == 1) {
        selectRole(roles.first.roleName);
      }
    } on AwsSsoException catch (e) {
      state = state.copyWith(
        error: e.message,
      );
    }
  }

  /// Select a role for credentials.
  void selectRole(String roleName) {
    state = state.copyWith(
      selectedRoleName: roleName,
      statusMessage: 'Ready to sync',
    );
  }

  /// Pull secrets from AWS Secrets Manager into the local vault.
  Future<AwsSyncResult> syncSecrets() async {
    if (_ssoService == null || !_ssoService!.hasValidToken) {
      state = state.copyWith(
        error: 'Not authenticated. Please connect first.',
        status: AwsConnectionStatus.error,
      );
      return const AwsSyncResult(error: 'Not authenticated');
    }

    if (state.selectedAccountId == null || state.selectedRoleName == null) {
      state = state.copyWith(
        error: 'Please select an account and role first.',
      );
      return const AwsSyncResult(error: 'No account/role selected');
    }

    state = state.copyWith(
      status: AwsConnectionStatus.syncing,
      statusMessage: 'Getting credentials...',
      clearError: true,
    );

    try {
      // Get temporary credentials
      final credentials = await _ssoService!.getRoleCredentials(
        accountId: state.selectedAccountId!,
        roleName: state.selectedRoleName!,
      );

      state = state.copyWith(statusMessage: 'Listing secrets...');

      // List secrets
      final smService = AwsSecretsManagerService(region: state.region);
      final secretsList = await smService.listSecrets(credentials);

      state = state.copyWith(
        statusMessage: 'Pulling ${secretsList.length} secrets...',
      );

      // Get existing vault entries to detect updates vs creates
      final vaultActions = _ref.read(vaultActionsProvider);
      final existingEntries =
          _ref.read(vaultEntriesProvider).valueOrNull ?? [];

      // Build a map of existing entries by their AWS ARN (stored in url field)
      final existingByArn = <String, VaultEntry>{};
      for (final entry in existingEntries) {
        if (entry.url.startsWith('arn:aws:secretsmanager:')) {
          existingByArn[entry.url] = entry;
        }
      }

      var created = 0;
      var updated = 0;
      var failed = 0;

      for (var i = 0; i < secretsList.length; i++) {
        state = state.copyWith(
          statusMessage:
              'Pulling secret ${i + 1}/${secretsList.length}...',
        );

        try {
          final secretWithValue =
              await smService.getSecretValue(credentials, secretsList[i]);

          final secretValue = secretWithValue.secretString ?? '';

          // Build tags from AWS tags + aws-sync marker
          final tagParts = ['aws-sync'];
          for (final t in secretWithValue.tags) {
            tagParts.add(t);
          }
          final tagsStr = tagParts.join(', ');

          final now = DateTime.now();

          if (existingByArn.containsKey(secretWithValue.arn)) {
            // Update existing entry
            final existing = existingByArn[secretWithValue.arn]!;
            await vaultActions.updateEntry(existing.copyWith(
              title: secretWithValue.name,
              password: secretValue,
              notes: secretWithValue.description ?? existing.notes,
              category: 'AWS-SM',
              tags: tagsStr,
              updatedAt: now,
            ));
            updated++;
          } else {
            // Create new entry
            var entry = VaultEntry(
              id: '',
              title: secretWithValue.name,
              username: '',
              password: secretValue,
              url: secretWithValue.arn,
              notes: secretWithValue.description ?? '',
              category: 'AWS-SM',
              tags: tagsStr,
              createdAt: now,
              updatedAt: now,
            );
            final newId = await vaultActions.addEntry(entry);
            entry = entry.copyWith(id: newId);

            // Index for RAG
            await _ref.read(embeddingIndexProvider.notifier).indexEntry(entry);

            created++;
          }
        } catch (_) {
          failed++;
        }
      }

      final result = AwsSyncResult(
        created: created,
        updated: updated,
        failed: failed,
        total: secretsList.length,
      );

      state = state.copyWith(
        status: AwsConnectionStatus.authenticated,
        statusMessage: 'Sync complete',
        lastSyncAt: DateTime.now(),
        lastSyncResult: result,
      );

      await _ref.read(auditLoggerProvider).log(
        action: AuditAction.awsSyncCompleted,
        details: '${result.created} created, ${result.updated} updated, ${result.failed} failed',
      );

      smService.dispose();
      return result;
    } on AwsSsoException catch (e) {
      final result = AwsSyncResult(error: e.message);
      state = state.copyWith(
        status: AwsConnectionStatus.error,
        error: e.message,
        lastSyncResult: result,
      );
      return result;
    } on AwsSecretsManagerException catch (e) {
      final result = AwsSyncResult(error: e.message);
      state = state.copyWith(
        status: AwsConnectionStatus.error,
        error: e.message,
        lastSyncResult: result,
      );
      return result;
    } catch (e) {
      final result = AwsSyncResult(error: e.toString());
      state = state.copyWith(
        status: AwsConnectionStatus.error,
        error: e.toString(),
        lastSyncResult: result,
      );
      return result;
    }
  }

  /// Disconnect from AWS SSO.
  void disconnect() {
    _ssoService?.disconnect();
    _ssoService = null;

    _ref.read(auditLoggerProvider).log(action: AuditAction.awsDisconnected);

    state = state.copyWith(
      status: AwsConnectionStatus.disconnected,
      clearError: true,
      clearUserCode: true,
      clearStatusMessage: true,
      accounts: const [],
      roles: const [],
    );
    // Reset selected account/role by rebuilding state
    state = AwsState(
      ssoStartUrl: state.ssoStartUrl,
      region: state.region,
      lastSyncAt: state.lastSyncAt,
      lastSyncResult: state.lastSyncResult,
    );
  }

  @override
  void dispose() {
    _ssoService?.dispose();
    super.dispose();
  }
}
