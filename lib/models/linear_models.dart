import 'package:flutter/material.dart';

/// Workflow state for a Linear issue.
class LinearIssueState {
  final String id;
  final String name;
  final String color; // hex like '#FF5733'
  final String type; // triage, backlog, unstarted, started, completed, cancelled

  const LinearIssueState({
    required this.id,
    required this.name,
    required this.color,
    required this.type,
  });

  Color get flutterColor {
    try {
      final hex = color.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  bool get isCompleted => type == 'completed';
  bool get isCancelled => type == 'cancelled';
  bool get isInProgress => type == 'started';

  factory LinearIssueState.fromJson(Map<String, dynamic> json) {
    return LinearIssueState(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as String? ?? '#CCCCCC',
      type: json['type'] as String? ?? 'backlog',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'type': type,
      };
}

/// A Linear team member.
class LinearMember {
  final String id;
  final String name;
  final String? email;

  const LinearMember({
    required this.id,
    required this.name,
    this.email,
  });

  factory LinearMember.fromJson(Map<String, dynamic> json) {
    return LinearMember(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (email != null) 'email': email,
      };
}

/// A Linear team.
class LinearTeam {
  final String id;
  final String name;
  final String key;
  final List<LinearIssueState> states;

  const LinearTeam({
    required this.id,
    required this.name,
    required this.key,
    this.states = const [],
  });

  factory LinearTeam.fromJson(Map<String, dynamic> json) {
    final statesNode =
        (json['states'] as Map<String, dynamic>?)?['nodes'] as List<dynamic>?;
    return LinearTeam(
      id: json['id'] as String,
      name: json['name'] as String,
      key: json['key'] as String,
      states: statesNode
              ?.map((s) =>
                  LinearIssueState.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'key': key,
        'states': {'nodes': states.map((s) => s.toJson()).toList()},
      };
}

/// A Linear project.
class LinearProject {
  final String id;
  final String name;
  final String state; // planned, started, paused, completed, cancelled
  final String? color;

  const LinearProject({
    required this.id,
    required this.name,
    required this.state,
    this.color,
  });

  Color? get flutterColor {
    if (color == null) return null;
    try {
      final hex = color!.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return null;
    }
  }

  factory LinearProject.fromJson(Map<String, dynamic> json) {
    return LinearProject(
      id: json['id'] as String,
      name: json['name'] as String,
      state: json['state'] as String? ?? 'started',
      color: json['color'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'state': state,
        if (color != null) 'color': color,
      };
}

/// Priority level for a Linear issue.
enum LinearPriority {
  noPriority(0, 'No Priority', Colors.grey),
  urgent(1, 'Urgent', Colors.red),
  high(2, 'High', Colors.orange),
  medium(3, 'Medium', Colors.blue),
  low(4, 'Low', Colors.grey);

  final int value;
  final String label;
  final Color color;

  const LinearPriority(this.value, this.label, this.color);

  static LinearPriority fromValue(int value) {
    return LinearPriority.values.firstWhere(
      (p) => p.value == value,
      orElse: () => LinearPriority.noPriority,
    );
  }
}

/// A Linear issue (task).
class LinearIssue {
  final String id;
  final String identifier; // e.g. ENG-123
  final String title;
  final String? description;
  final int priorityValue;
  final LinearIssueState state;
  final LinearMember? assignee;
  final LinearTeam team;
  final LinearProject? project;
  final DateTime? dueDate;
  final String url;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LinearIssue({
    required this.id,
    required this.identifier,
    required this.title,
    this.description,
    required this.priorityValue,
    required this.state,
    this.assignee,
    required this.team,
    this.project,
    this.dueDate,
    required this.url,
    required this.createdAt,
    required this.updatedAt,
  });

  LinearPriority get priority => LinearPriority.fromValue(priorityValue);

  bool get isOverdue =>
      dueDate != null &&
      dueDate!.isBefore(DateTime.now()) &&
      !state.isCompleted &&
      !state.isCancelled;

  bool get isDueSoon =>
      dueDate != null &&
      !isOverdue &&
      dueDate!.isBefore(DateTime.now().add(const Duration(days: 3))) &&
      !state.isCompleted &&
      !state.isCancelled;

  factory LinearIssue.fromJson(Map<String, dynamic> json) {
    final stateJson = json['state'] as Map<String, dynamic>?;
    final assigneeJson = json['assignee'] as Map<String, dynamic>?;
    final teamJson = json['team'] as Map<String, dynamic>;
    final projectJson = json['project'] as Map<String, dynamic>?;

    DateTime? dueDate;
    final dueDateStr = json['dueDate'] as String?;
    if (dueDateStr != null) {
      try {
        dueDate = DateTime.parse(dueDateStr);
      } catch (_) {}
    }

    return LinearIssue(
      id: json['id'] as String,
      identifier: json['identifier'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      priorityValue: (json['priority'] as int?) ?? 0,
      state: stateJson != null
          ? LinearIssueState.fromJson(stateJson)
          : const LinearIssueState(
              id: '',
              name: 'Unknown',
              color: '#CCCCCC',
              type: 'backlog',
            ),
      assignee:
          assigneeJson != null ? LinearMember.fromJson(assigneeJson) : null,
      team: LinearTeam.fromJson(teamJson),
      project:
          projectJson != null ? LinearProject.fromJson(projectJson) : null,
      dueDate: dueDate,
      url: json['url'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'identifier': identifier,
        'title': title,
        if (description != null) 'description': description,
        'priority': priorityValue,
        'state': state.toJson(),
        if (assignee != null) 'assignee': assignee!.toJson(),
        'team': team.toJson(),
        if (project != null) 'project': project!.toJson(),
        if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
        'url': url,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  String get chatContext {
    final parts = <String>[
      '[$identifier] $title',
      'Status: ${state.name}',
      'Priority: ${priority.label}',
      if (assignee != null) 'Assignee: ${assignee!.name}',
      if (project != null) 'Project: ${project!.name}',
      'Team: ${team.name}',
      if (dueDate != null)
        'Due: ${dueDate!.year}-${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}',
      if (description != null && description!.isNotEmpty)
        'Description: ${description!.length > 200 ? '${description!.substring(0, 200)}...' : description}',
    ];
    return parts.join('\n');
  }
}

/// Info about the connected Linear workspace/user.
class LinearViewer {
  final String id;
  final String name;
  final String email;
  final String organizationId;
  final String organizationName;
  final String organizationUrlKey;

  const LinearViewer({
    required this.id,
    required this.name,
    required this.email,
    required this.organizationId,
    required this.organizationName,
    required this.organizationUrlKey,
  });

  factory LinearViewer.fromJson(Map<String, dynamic> json) {
    final org = json['organization'] as Map<String, dynamic>? ?? {};
    return LinearViewer(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String? ?? '',
      organizationId: org['id'] as String? ?? '',
      organizationName: org['name'] as String? ?? '',
      organizationUrlKey: org['urlKey'] as String? ?? '',
    );
  }
}
