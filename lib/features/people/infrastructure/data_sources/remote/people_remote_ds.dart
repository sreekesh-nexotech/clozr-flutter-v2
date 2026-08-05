import 'dart:math';

import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/app_error.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/member.dart';
import '../../../domain/entities/role.dart';
import '../../../domain/entities/team.dart';

/// Raw People endpoints (management users / teams / roles). HTTP + JSON→entity
/// mapping only — caching and orchestration live in `PeopleApiRepository`.
///
/// Reads return the raw JSON rows so the repository can persist them in the
/// Hive cache; the static `*FromJson` mappers turn those rows into the
/// existing domain entities (also used against the cached copies and in unit
/// tests).
class PeopleRemoteDataSource {
  const PeopleRemoteDataSource(this._api);

  final ApiService _api;

  /// The UI's providers expect a full in-memory list — follow `next` up to a
  /// sane cap instead of paging forever.
  static const int _maxPages = 50; // safety cap; loop still breaks when next == null

  // ── Reads (raw rows; the repository caches these) ──

  /// `GET /management/users/` — org member list, paginated.
  Future<List<Map<String, dynamic>>> fetchMemberRows() =>
      _pagedRows(ApiEndpoints.users);

  /// `GET /management/teams/` — org team list, paginated.
  Future<List<Map<String, dynamic>>> fetchTeamRows() =>
      _pagedRows(ApiEndpoints.teams);

  /// `GET /management/teams/members/` — every `TeamMember` row org-wide, flat.
  /// Fetched once and grouped client-side (no per-team N+1).
  Future<List<Map<String, dynamic>>> fetchTeamMemberRows() =>
      _pagedRows(ApiEndpoints.allTeamMembers);

  /// `GET /management/roles/` — seeded + custom roles, paginated.
  Future<List<Map<String, dynamic>>> fetchRoleRows() =>
      _pagedRows(ApiEndpoints.roles);

  /// `GET /crm/dashboard-crm/member-performance/` — owned-lead metrics for one
  /// member, all-time. 403-safe: non-admins without KPI access get null (the
  /// detail screen simply keeps the entity's zero defaults). Never called at
  /// list time — that would be an N+1.
  Future<Map<String, dynamic>?> fetchMemberPerformance(String userId) async {
    try {
      final body = await _api.get(
        ApiEndpoints.memberPerformance,
        query: {'user_id': userId, 'period': 'all_time'},
      );
      return body is Map<String, dynamic> ? body : null;
    } on AppError {
      return null; // Performance is a nicety, never a blocker.
    }
  }

  // ── Writes ──

  /// `POST /management/users/` — invite a member. The backend requires the
  /// client to supply `user_id`; the member is created inactive and receives
  /// an activation email (the "Invited" state). The 201 arrives wrapped as
  /// `{message, user}` — nothing to map, the list refetches.
  Future<void> inviteMember({
    required String email,
    required String name,
    String? phone,
    String? roleId,
  }) async {
    final parts = name.trim().split(RegExp(r'\s+'));
    final firstName = parts.isEmpty ? '' : parts.first;
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    await _api.post(ApiEndpoints.users, body: {
      'user_id': generateUuid(),
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (roleId != null && roleId.isNotEmpty) 'role_id': roleId,
    });
  }

  /// `POST /management/teams/` — create a team. Only non-null fields are sent.
  Future<Team?> createTeam({
    required String name,
    String? description,
    String? leadUserId,
  }) async {
    final body = await _api.post(ApiEndpoints.teams, body: {
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (leadUserId != null && leadUserId.isNotEmpty) 'manager_id': leadUserId,
    });
    return body is Map<String, dynamic> ? teamFromJson(body, const {}) : null;
  }

  /// `POST /management/roles/` — create a custom role granting the CRM card
  /// with hierarchy visibility (the mobile Add-role sheet's fixed grant).
  Future<void> createRole({required String name, String? description}) async {
    await _api.post(ApiEndpoints.roles, body: {
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      'module_groups': [
        {'group': 'crm', 'visibility': 'hierarchy'},
      ],
    });
  }

  // ── Mapping (static so the repository can re-map cached rows and tests can
  //    exercise fixtures directly) ──

  /// Maps a list of raw rows, skipping malformed entries instead of crashing.
  static List<Member> membersFromRows(List<dynamic> rows) {
    final out = <Member>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final member = memberFromJson(row);
      if (member != null) out.add(member);
    }
    return out;
  }

  /// One member row → [Member]. Returns null (row skipped) when `user_id` is
  /// missing. `scope` is a detail-only field — on list rows the fallback `'—'`
  /// renders. Also registers the member in [UserDirectory] so names/initials
  /// resolve app-wide.
  static Member? memberFromJson(Map<String, dynamic> json) {
    final id = json['user_id'] as String? ?? '';
    if (id.isEmpty) return null;

    final name = (json['full_name'] as String?) ??
        [json['first_name'], json['last_name']]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' ');

    final role = json['role'];
    final roleName = role is Map ? (role['name'] as String? ?? 'Viewer') : 'Viewer';

    final scope = json['scope'];
    final manager = json['manager'];
    final teams = json['teams'];
    var team = '—';
    if (teams is List && teams.isNotEmpty && teams.first is Map) {
      team = ((teams.first as Map)['name'] as String?) ?? '—';
    }

    final profile = json['profile'];
    var phone = '';
    if (profile is Map) {
      phone = (profile['phone'] as String?) ?? '';
      if (phone.isEmpty) phone = (profile['mobile'] as String?) ?? '';
    }

    UserDirectory.register(userId: id, fullName: name, role: roleName);

    return Member(
      id: id,
      name: name,
      email: json['email'] as String? ?? '',
      phone: phone,
      role: roleName,
      scope: scope is Map ? (scope['label'] as String? ?? '—') : '—',
      reportsTo:
          manager is Map ? (manager['full_name'] as String? ?? '— (exempt)') : '— (exempt)',
      team: team,
      status: json['is_active'] == true ? 'active' : 'invited',
    );
  }

  /// Overlays a member-performance payload onto an existing [Member].
  static Member applyPerformance(Member m, Map<String, dynamic> json) {
    final owned = json['owned_leads'];
    final open = owned is Map ? (owned['open'] as num?)?.toInt() ?? 0 : 0;
    final closed = owned is Map ? (owned['closed'] as num?)?.toInt() ?? 0 : 0;
    final wonValue = parseAmount(json['deal_value_won']);
    final conversion = json['conversion_rate'];
    return Member(
      id: m.id,
      name: m.name,
      email: m.email,
      phone: m.phone,
      role: m.role,
      scope: m.scope,
      reportsTo: m.reportsTo,
      team: m.team,
      status: m.status,
      perfOpen: open,
      perfClosed: closed,
      perfWon: (json['deals_won'] as num?)?.toInt() ?? 0,
      perfWonVal: wonValue > 0 ? formatInr(wonValue) : '₹0L',
      perfConv: conversion is num ? _percent(conversion) : '—',
    );
  }

  /// Groups the org-wide flat `TeamMember` rows into `{team_id: [user_id]}`.
  /// Embedded user objects are registered so the team cards resolve names.
  static Map<String, List<String>> groupTeamMembers(List<dynamic> rows) {
    final byTeam = <String, List<String>>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final teamId = row['team_id'] as String? ?? '';
      final userId = row['user_id'] as String? ?? '';
      if (teamId.isEmpty || userId.isEmpty) continue;
      final ids = byTeam.putIfAbsent(teamId, () => <String>[]);
      if (!ids.contains(userId)) ids.add(userId);
      UserDirectory.registerJson(row['user']);
    }
    return byTeam;
  }

  /// One team row → [Team]. `membersByTeam` comes from [groupTeamMembers].
  static Team? teamFromJson(
    Map<String, dynamic> json,
    Map<String, List<String>> membersByTeam,
  ) {
    final id = json['team_id'] as String? ?? '';
    if (id.isEmpty) return null;
    final manager = json['manager'];
    UserDirectory.registerJson(manager);
    return Team(
      id: id,
      name: json['name'] as String? ?? '',
      zone: json['description'] as String? ?? '',
      lead: manager is Map ? (manager['user_id'] as String? ?? '') : '',
      members: membersByTeam[id] ?? const [],
    );
  }

  /// One role row → [Role]. Seeded roles (`is_editable == false`) are locked.
  static Role? roleFromJson(Map<String, dynamic> json) {
    final id = json['role_id'] as String? ?? '';
    if (id.isEmpty) return null;

    final caps = <String>[];
    final grouped = json['grouped_permissions'];
    if (grouped is List) {
      for (final group in grouped) {
        if (group is Map && group['group'] is String) {
          final label = (group['group'] as String).toUpperCase();
          if (label.isNotEmpty && !caps.contains(label)) caps.add(label);
        }
      }
    }

    return Role(
      id: id,
      name: json['name'] as String? ?? '',
      locked: json['is_editable'] == false,
      scope: _roleScope(json),
      desc: json['description'] as String? ?? '',
      caps: caps,
    );
  }

  /// `permission_type` code → the visibility label the UI renders.
  static const Map<String, String> _scopeLabels = {
    'all': 'Organization-wide',
    'hierarchy': 'Self + Reporting Hierarchy',
    'team': 'Team-based + Reporting Hierarchy',
    'owned': 'Owned Records',
    'assignee': 'Assigned Records',
    'filtered': 'Filtered Records',
  };

  /// Derives a role's visibility scope from its lead-module record permission
  /// (the same signal the web app's sub-label uses). Roles with no lead scope
  /// (e.g. the seeded Admin, whose access is the `is_staff` bypass) read as
  /// Organization-wide when they look full-access, `'—'` otherwise.
  static String _roleScope(Map<String, dynamic> json) {
    String? leadType(Object? rows) {
      if (rows is! List) return null;
      for (final row in rows) {
        if (row is Map &&
            row['module_name'] == 'lead' &&
            row['permission_type'] is String) {
          return row['permission_type'] as String;
        }
      }
      return null;
    }

    var type = leadType(json['record_permissions']);
    if (type == null) {
      final grouped = json['grouped_permissions'];
      if (grouped is List) {
        for (final group in grouped) {
          if (group is Map) {
            type = leadType(group['modules']);
            if (type != null) break;
          }
        }
      }
    }

    final label = type == null ? null : _scopeLabels[type];
    if (label != null) return label;
    final level = (json['permission_level'] as num?)?.toInt() ?? 0;
    return level >= 100 ? 'Organization-wide' : '—';
  }

  // ── Helpers ──

  /// RFC-4122-shaped v4 uuid from random bytes XOR-mixed with the clock — the
  /// invite endpoint requires a client-supplied `user_id` and the app carries
  /// no uuid dependency.
  static String generateUuid() {
    final rng = Random();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    final now = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < 8; i++) {
      bytes[i] ^= (now >> (i * 8)) & 0xff;
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String _percent(num value) {
    final v = value.toDouble();
    return v == v.roundToDouble() ? '${v.toInt()}%' : '${v.toStringAsFixed(1)}%';
  }

  Future<List<Map<String, dynamic>>> _pagedRows(String path) async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; page <= _maxPages; page++) {
      final body = await _api.get(path, query: {
        'page': page,
        'page_size': ApiConfig.defaultPageSize,
      });
      if (body is! Map<String, dynamic>) break;
      final results = body['results'];
      if (results is List) {
        rows.addAll(results.whereType<Map<String, dynamic>>());
      }
      if (body['next'] == null) break;
    }
    return rows;
  }
}
