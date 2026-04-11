import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/linear_models.dart';
import '../services/linear_service.dart';
import 'audit_provider.dart';

// ---------------------------------------------------------------------------
// Connection Status
// ---------------------------------------------------------------------------

enum LinearConnectionStatus {
  disconnected,
  connecting,
  authenticated,
  syncing,
  error,
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class LinearState {
  final String clientId;
  final String clientSecret;
  final LinearConnectionStatus status;
  final String? statusMessage;
  final String? error;

  // Connected workspace info
  final LinearViewer? viewer;

  // Data
  final List<LinearTeam> teams;
  final List<LinearProject> projects;
  final List<LinearIssue> issues;

  // Filters
  final String? selectedTeamId;
  final String? selectedProjectId;
  final bool showOnlyMine;

  // Sync tracking
  final DateTime? lastSyncAt;

  const LinearState({
    this.clientId = '',
    this.clientSecret = '',
    this.status = LinearConnectionStatus.disconnected,
    this.statusMessage,
    this.error,
    this.viewer,
    this.teams = const [],
    this.projects = const [],
    this.issues = const [],
    this.selectedTeamId,
    this.selectedProjectId,
    this.showOnlyMine = false,
    this.lastSyncAt,
  });

  bool get isConnected =>
      status == LinearConnectionStatus.authenticated ||
      status == LinearConnectionStatus.syncing;

  LinearState copyWith({
    String? clientId,
    String? clientSecret,
    LinearConnectionStatus? status,
    String? statusMessage,
    String? error,
    LinearViewer? viewer,
    List<LinearTeam>? teams,
    List<LinearProject>? projects,
    List<LinearIssue>? issues,
    String? selectedTeamId,
    String? selectedProjectId,
    bool? showOnlyMine,
    DateTime? lastSyncAt,
    bool clearError = false,
    bool clearStatusMessage = false,
    bool clearSelectedTeam = false,
    bool clearSelectedProject = false,
  }) {
    return LinearState(
      clientId: clientId ?? this.clientId,
      clientSecret: clientSecret ?? this.clientSecret,
      status: status ?? this.status,
      statusMessage:
          clearStatusMessage ? null : (statusMessage ?? this.statusMessage),
      error: clearError ? null : (error ?? this.error),
      viewer: viewer ?? this.viewer,
      teams: teams ?? this.teams,
      projects: projects ?? this.projects,
      issues: issues ?? this.issues,
      selectedTeamId:
          clearSelectedTeam ? null : (selectedTeamId ?? this.selectedTeamId),
      selectedProjectId: clearSelectedProject
          ? null
          : (selectedProjectId ?? this.selectedProjectId),
      showOnlyMine: showOnlyMine ?? this.showOnlyMine,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  /// Issues filtered by current team/project selection.
  List<LinearIssue> get filteredIssues {
    var result = issues;
    if (selectedTeamId != null) {
      result = result.where((i) => i.team.id == selectedTeamId).toList();
    }
    if (selectedProjectId != null) {
      result =
          result.where((i) => i.project?.id == selectedProjectId).toList();
    }
    if (showOnlyMine && viewer != null) {
      result = result.where((i) => i.assignee?.id == viewer!.id).toList();
    }
    return result;
  }

  /// Active issues (not completed/cancelled).
  List<LinearIssue> get activeIssues => filteredIssues
      .where((i) => !i.state.isCompleted && !i.state.isCancelled)
      .toList();

  /// Issues grouped by state type.
  Map<String, List<LinearIssue>> get issuesByStateType {
    final grouped = <String, List<LinearIssue>>{};
    for (final issue in filteredIssues) {
      final type = issue.state.type;
      grouped.putIfAbsent(type, () => []).add(issue);
    }
    return grouped;
  }

  /// Unique teams present in the issues list.
  List<LinearTeam> get teamsFromIssues {
    final seen = <String>{};
    final result = <LinearTeam>[];
    for (final issue in issues) {
      if (seen.add(issue.team.id)) {
        result.add(issue.team);
      }
    }
    return result;
  }

  /// Unique projects present in the issues list.
  List<LinearProject> get projectsFromIssues {
    final seen = <String>{};
    final result = <LinearProject>[];
    for (final issue in issues) {
      if (issue.project != null && seen.add(issue.project!.id)) {
        result.add(issue.project!);
      }
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final linearProvider =
    StateNotifierProvider<LinearNotifier, LinearState>((ref) {
  return LinearNotifier(ref);
});

class LinearNotifier extends StateNotifier<LinearState> {
  final Ref _ref;
  LinearService? _service;

  LinearNotifier(this._ref) : super(const LinearState()) {
    _loadConfig();
  }

  // ---------------------------------------------------------------------------
  // Config Persistence
  // ---------------------------------------------------------------------------

  static const _kClientId = 'linear_client_id';
  static const _kClientSecret = 'linear_client_secret';
  static const _kAccessToken = 'linear_access_token';
  static const _kCachedTeams = 'linear_cached_teams';
  static const _kCachedProjects = 'linear_cached_projects';
  static const _kCachedIssues = 'linear_cached_issues';
  static const _kLastSyncAt = 'linear_last_sync_at';

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getString(_kClientId) ?? '';
    final clientSecret = prefs.getString(_kClientSecret) ?? '';
    final token = prefs.getString(_kAccessToken);
    final lastSyncStr = prefs.getString(_kLastSyncAt);

    state = state.copyWith(
      clientId: clientId,
      clientSecret: clientSecret,
      lastSyncAt: lastSyncStr != null ? DateTime.tryParse(lastSyncStr) : null,
    );

    if (token != null && token.isNotEmpty) {
      _service = LinearService();
      _service!.restoreToken(token);

      // Restore cached data
      _restoreCachedData(prefs);

      state = state.copyWith(
        status: LinearConnectionStatus.authenticated,
        statusMessage: 'Restored from last session',
      );

      // Refresh viewer info in background
      _refreshViewer();
    }
  }

  void _restoreCachedData(SharedPreferences prefs) {
    try {
      final teamsJson = prefs.getString(_kCachedTeams);
      if (teamsJson != null) {
        final teamsList = jsonDecode(teamsJson) as List<dynamic>;
        final teams = teamsList
            .map((t) => LinearTeam.fromJson(t as Map<String, dynamic>))
            .toList();
        state = state.copyWith(teams: teams);
      }

      final projectsJson = prefs.getString(_kCachedProjects);
      if (projectsJson != null) {
        final projectsList = jsonDecode(projectsJson) as List<dynamic>;
        final projects = projectsList
            .map((p) => LinearProject.fromJson(p as Map<String, dynamic>))
            .toList();
        state = state.copyWith(projects: projects);
      }

      final issuesJson = prefs.getString(_kCachedIssues);
      if (issuesJson != null) {
        final issuesList = jsonDecode(issuesJson) as List<dynamic>;
        final issues = issuesList
            .map((i) => LinearIssue.fromJson(i as Map<String, dynamic>))
            .toList();
        state = state.copyWith(issues: issues);
      }
    } catch (_) {
      // Ignore cache parse errors
    }
  }

  Future<void> _refreshViewer() async {
    try {
      final viewer = await _service!.getViewer();
      state = state.copyWith(viewer: viewer);
    } catch (_) {
      // Non-critical — viewer info is just for display
    }
  }

  Future<void> _saveConfig({
    String? clientId,
    String? clientSecret,
    String? token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (clientId != null) await prefs.setString(_kClientId, clientId);
    if (clientSecret != null) {
      await prefs.setString(_kClientSecret, clientSecret);
    }
    if (token != null) {
      await prefs.setString(_kAccessToken, token);
    }
  }

  Future<void> _saveCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCachedTeams,
        jsonEncode(state.teams.map((t) => t.toJson()).toList()),
      );
      await prefs.setString(
        _kCachedProjects,
        jsonEncode(state.projects.map((p) => p.toJson()).toList()),
      );
      // Only cache up to 200 issues to avoid SharedPreferences size limits
      final issuesToCache = state.issues.take(200).toList();
      await prefs.setString(
        _kCachedIssues,
        jsonEncode(issuesToCache.map((i) => i.toJson()).toList()),
      );
      await prefs.setString(
        _kLastSyncAt,
        state.lastSyncAt?.toIso8601String() ?? '',
      );
    } catch (_) {
      // Cache failures are non-fatal
    }
  }

  // ---------------------------------------------------------------------------
  // Public Config Setters
  // ---------------------------------------------------------------------------

  Future<void> setCredentials(String clientId, String clientSecret) async {
    await _saveConfig(clientId: clientId, clientSecret: clientSecret);
    state = state.copyWith(
      clientId: clientId,
      clientSecret: clientSecret,
    );
  }

  // ---------------------------------------------------------------------------
  // OAuth Connect
  // ---------------------------------------------------------------------------

  Future<void> connect() async {
    if (state.clientId.isEmpty || state.clientSecret.isEmpty) {
      state = state.copyWith(
        error: 'Please enter your Linear Client ID and Client Secret first.',
        status: LinearConnectionStatus.error,
      );
      return;
    }

    state = state.copyWith(
      status: LinearConnectionStatus.connecting,
      clearError: true,
    );

    _service?.dispose();
    _service = LinearService();

    try {
      final token = await _service!.authenticate(
        clientId: state.clientId,
        clientSecret: state.clientSecret,
        onStatusChanged: (msg) {
          state = state.copyWith(statusMessage: msg);
        },
      );

      await _saveConfig(token: token);

      state = state.copyWith(
        status: LinearConnectionStatus.authenticated,
        statusMessage: 'Connected! Loading workspace...',
      );

      await _ref.read(auditLoggerProvider).log(
            action: AuditAction.linearConnected,
          );

      // Load viewer + initial data
      await _refreshViewer();
      await sync();
    } on LinearException catch (e) {
      state = state.copyWith(
        status: LinearConnectionStatus.error,
        error: '${e.message}\n${e.details}',
        clearStatusMessage: true,
      );
    } catch (e) {
      state = state.copyWith(
        status: LinearConnectionStatus.error,
        error: e.toString(),
        clearStatusMessage: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  Future<void> sync() async {
    if (_service == null || !_service!.isAuthenticated) {
      state = state.copyWith(
        error: 'Not connected. Please connect first.',
        status: LinearConnectionStatus.error,
      );
      return;
    }

    state = state.copyWith(
      status: LinearConnectionStatus.syncing,
      statusMessage: 'Loading teams...',
      clearError: true,
    );

    try {
      final teams = await _service!.getTeams();
      state = state.copyWith(teams: teams, statusMessage: 'Loading projects...');

      final projects = await _service!.getProjects();
      state = state.copyWith(
          projects: projects, statusMessage: 'Loading issues...');

      final issues = await _service!.getIssues();
      final now = DateTime.now();

      state = state.copyWith(
        issues: issues,
        status: LinearConnectionStatus.authenticated,
        statusMessage: '${issues.length} issues loaded',
        lastSyncAt: now,
      );

      await _saveCachedData();

      await _ref.read(auditLoggerProvider).log(
            action: AuditAction.linearSynced,
            details: '${issues.length} issues',
          );
    } on LinearException catch (e) {
      state = state.copyWith(
        status: LinearConnectionStatus.error,
        error: '${e.message}: ${e.details}',
        clearStatusMessage: true,
      );
    } catch (e) {
      state = state.copyWith(
        status: LinearConnectionStatus.error,
        error: e.toString(),
        clearStatusMessage: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Issue Actions
  // ---------------------------------------------------------------------------

  Future<LinearIssue?> createIssue({
    required String teamId,
    required String title,
    String? description,
    String? stateId,
    int priority = 0,
    String? assigneeId,
    String? projectId,
    DateTime? dueDate,
  }) async {
    if (_service == null) return null;
    try {
      final issue = await _service!.createIssue(
        teamId: teamId,
        title: title,
        description: description,
        stateId: stateId,
        priority: priority,
        assigneeId: assigneeId,
        projectId: projectId,
        dueDate: dueDate,
      );
      // Prepend to issues list
      state = state.copyWith(issues: [issue, ...state.issues]);
      await _saveCachedData();

      await _ref.read(auditLoggerProvider).log(
            action: AuditAction.linearIssueCreated,
            targetId: issue.id,
            targetName: issue.identifier,
            details: title,
          );
      return issue;
    } on LinearException catch (e) {
      state = state.copyWith(error: '${e.message}: ${e.details}');
      return null;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<void> updateIssueState({
    required String issueId,
    required String stateId,
  }) async {
    if (_service == null) return;
    try {
      final updated = await _service!.updateIssueState(
        issueId: issueId,
        stateId: stateId,
      );
      // Replace in list
      state = state.copyWith(
        issues: state.issues
            .map((i) => i.id == issueId ? updated : i)
            .toList(),
      );
      await _saveCachedData();
    } on LinearException catch (e) {
      state = state.copyWith(error: '${e.message}: ${e.details}');
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Filters
  // ---------------------------------------------------------------------------

  void setTeamFilter(String? teamId) {
    state = teamId == null
        ? state.copyWith(clearSelectedTeam: true)
        : state.copyWith(selectedTeamId: teamId);
  }

  void setProjectFilter(String? projectId) {
    state = projectId == null
        ? state.copyWith(clearSelectedProject: true)
        : state.copyWith(selectedProjectId: projectId);
  }

  void toggleMyIssues() {
    state = state.copyWith(showOnlyMine: !state.showOnlyMine);
  }

  // ---------------------------------------------------------------------------
  // Disconnect
  // ---------------------------------------------------------------------------

  Future<void> disconnect() async {
    _service?.dispose();
    _service = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kCachedTeams);
    await prefs.remove(_kCachedProjects);
    await prefs.remove(_kCachedIssues);
    await prefs.remove(_kLastSyncAt);

    await _ref.read(auditLoggerProvider).log(
          action: AuditAction.linearDisconnected,
        );

    state = LinearState(
      clientId: state.clientId,
      clientSecret: state.clientSecret,
    );
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }
}
