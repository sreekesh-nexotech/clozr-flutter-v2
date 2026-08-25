import 'dart:math';

import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/app_error.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/member.dart';
import '../../../domain/entities/module_catalog.dart';
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

  /// `GET /management/users/` — the org's members, paginated.
  ///
  /// **Two calls, merged.** The endpoint returns only **active** members unless
  /// `is_active` is supplied (`members.md` §Status), so the plain list can never
  /// contain a deactivated or a not-yet-activated member. The second pass with
  /// `?is_active=false` is what makes the Status filter mean anything — without
  /// it the Invited and Deactivated chips match nothing, because those rows were
  /// never fetched.
  ///
  /// The second pass is best-effort: it is the *extra* half of the list, so a
  /// failure there should cost the inactive rows, not the whole screen.
  Future<List<Map<String, dynamic>>> fetchMemberRows() async {
    final rows = await _pagedRows(ApiEndpoints.users);
    try {
      rows.addAll(
        await _pagedRows(ApiEndpoints.users, query: {'is_active': false}),
      );
    } on AppError {
      // Keep the active members rather than failing the list.
    }
    // Defensive: an org that ignores the flag would otherwise double every row.
    final seen = <String>{};
    return [
      for (final row in rows)
        if (seen.add('${row['user_id']}')) row,
    ];
  }

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
  Future<Map<String, dynamic>?> fetchMemberPerformance(
    String userId, {
    String period = 'all_time',
  }) async {
    if (userId.isEmpty) return null;
    try {
      final body = await _api.get(
        ApiEndpoints.memberPerformance,
        query: {'user_id': userId, 'period': period},
      );
      return body is Map<String, dynamic> ? body : null;
    } on AppError {
      return null; // Performance is a nicety, never a blocker.
    }
  }

  /// `GET /management/users/{user_id}/` — one member, enriched
  /// (`members.md` §4.1).
  ///
  /// Worth its own call because the paginated list omits what the detail page
  /// needs: `scope` (a per-user permission lookup the list will not run),
  /// `is_protected`, `profile.designation`, `profile.timezone` and
  /// `territories`.
  ///
  /// Best-effort — the screen already has the list row to fall back on, so a
  /// failure costs the enrichment rather than the page.
  Future<Map<String, dynamic>?> fetchMemberRow(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final body = await _api.get(ApiEndpoints.user(userId));
      return body is Map<String, dynamic> ? body : null;
    } on AppError {
      return null;
    }
  }

  /// `GET /management/users/{user_id}/activity/` — the member's activity feed
  /// (`members.md` §4.3), newest first.
  ///
  /// Composed server-side from reliable lifecycle events (`joined` off
  /// `date_joined`, `login` off `last_login`) plus best-effort audit rows for
  /// role assignments and updates. The doc notes the audit half is written
  /// asynchronously and may be absent if the worker is down — joined/login
  /// always render.
  ///
  /// 403-safe like the performance call: a role without `view_user_management`
  /// gets an empty list rather than an error, and the card falls back.
  Future<List<Map<String, dynamic>>> fetchMemberActivity(String userId) async {
    if (userId.isEmpty) return const [];
    try {
      final body = await _api.get(ApiEndpoints.userActivity(userId),
          query: {'limit': 20});
      final results = body is Map<String, dynamic> ? body['results'] : body;
      return results is List
          ? results.whereType<Map<String, dynamic>>().toList()
          : const [];
    } on AppError {
      return const [];
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
    String? managerId,
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
      if (managerId != null && managerId.isNotEmpty) 'manager_id': managerId,
    });
  }

  /// `PATCH /management/users/{user_id}/` — edit a member (`members.md`
  /// §Edit member).
  ///
  /// Partial by design: only the fields the form actually changed are sent, so
  /// an untouched value is never rewritten with a stale copy.
  ///
  /// Two behaviours the caller has to know about, both documented:
  /// * `role_id` **replaces** the member's existing role.
  /// * `manager_id` closes the current hierarchy row and opens a new one,
  ///   recalculating the subtree's levels.
  ///
  /// Errors are not swallowed — a duplicate email is a `400` on the `email`
  /// key, and the message is the only thing that explains a failed save.
  Future<void> updateMember(
    String userId, {
    String? name,
    String? email,
    String? phone,
    String? roleId,
    String? managerId,
  }) async {
    final body = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) {
      final parts = name.trim().split(RegExp(r'\s+'));
      body['first_name'] = parts.first;
      body['last_name'] = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }
    if (email != null && email.trim().isNotEmpty) body['email'] = email.trim();
    // Sent even when blank: clearing a phone is a real edit, and the profile
    // write accepts an empty string for it.
    if (phone != null) body['phone'] = phone.trim();
    if (roleId != null && roleId.isNotEmpty) body['role_id'] = roleId;
    if (managerId != null && managerId.isNotEmpty) body['manager_id'] = managerId;
    if (body.isEmpty) return;
    await _api.patch(ApiEndpoints.user(userId), body: body);
  }

  /// `POST /management/teams/` — create a team. Only non-null fields are sent.
  Future<Team?> createTeam({
    required String name,
    String? description,
    String? leadUserId,
    List<String> memberIds = const [],
  }) async {
    final body = await _api.post(ApiEndpoints.teams, body: {
      'name': name,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (leadUserId != null && leadUserId.isNotEmpty) 'manager_id': leadUserId,
      // Write-only on create (`team-api.md` §1.2): the members to seed the team
      // with. Without it a new team is always created empty and every member has
      // to be added one at a time afterwards.
      if (memberIds.isNotEmpty) 'member_ids': memberIds,
    });
    return body is Map<String, dynamic> ? teamFromJson(body, const {}) : null;
  }

  /// `PATCH /management/teams/{team_id}/` — edit a team (`team-api.md` §1.5).
  ///
  /// Partial by design: only the fields the sheet actually changed are sent, so
  /// clearing the lead is distinguishable from not touching it. `member_ids` is
  /// a **full replacement** of the roster, not an addition (§1.5) — which is
  /// what an edit form showing the whole roster wants, and why it is only sent
  /// when the picker was opened and changed.
  Future<void> updateTeam(String id, Map<String, dynamic> fields) async {
    if (id.isEmpty || fields.isEmpty) return;
    await _api.patch(ApiEndpoints.team(id), body: fields);
  }

  /// `POST /management/teams/{team_id}/members/` — add one member
  /// (`team-api.md` §2.2).
  ///
  /// One call per user; the endpoint takes a single `user_id`. "Already a
  /// member" comes back as a 400, which the caller treats as success rather
  /// than an error — the desired end state is the same.
  Future<void> addTeamMember({required String teamId, required String userId}) async {
    if (teamId.isEmpty || userId.isEmpty) return;
    try {
      await _api.post(ApiEndpoints.teamMembers(teamId), body: {'user_id': userId});
    } on AppError catch (e) {
      final already = e.message.toLowerCase().contains('already');
      if (e.type != AppErrorType.validation || !already) rethrow;
    }
  }

  /// `DELETE /management/roles/{role_id}/` — delete a custom role
  /// (`roles.md` §6).
  ///
  /// Errors are **not** swallowed: a seeded role is a 403 and a role that still
  /// has members is a 409 carrying the count, and the screen has to say which.
  Future<void> deleteRole(String id) async {
    if (id.isEmpty) return;
    await _api.delete(ApiEndpoints.role(id));
  }

  /// `GET /management/permissions/module-catalog/` — the capability cards and
  /// visibility scopes the Add role form offers (`roles.md` §1).
  ///
  /// Best-effort: any failure yields the empty catalog, which the form reads as
  /// "use the built-in card set" rather than blocking role creation on it.
  Future<ModuleCatalog> fetchModuleCatalog() async {
    try {
      return ModuleCatalog.fromJson(await _api.get(ApiEndpoints.moduleCatalog));
    } on Object {
      return ModuleCatalog.empty;
    }
  }

  /// `POST /management/roles/` — creates a custom role granting the chosen
  /// capability cards at the chosen record scope.
  Future<void> createRole({
    required String name,
    String? description,
    Set<String> groups = const {},
    String visibility = 'hierarchy',
  }) async {
    await _api.post(
      ApiEndpoints.roles,
      body: roleCreateBody(
        name: name,
        description: description,
        groups: groups,
        visibility: visibility,
      ),
    );
  }

  /// `PATCH /management/roles/{id}/` — edits a **custom** role (`roles.md` §5).
  ///
  /// Same body as create. Supplying `module_groups` **replaces** the role's
  /// capability set rather than adding to it, so the form always sends the
  /// complete set of ticked cards.
  ///
  /// Errors are deliberately not swallowed: a seeded role rejects the edit with
  /// `403 "Seeded roles cannot be edited."`, and a duplicate name is a `400` —
  /// both are the only explanation the user would get.
  Future<void> updateRole(
    String id, {
    required String name,
    String? description,
    Set<String> groups = const {},
    String visibility = 'hierarchy',
  }) async {
    await _api.patch(
      ApiEndpoints.role(id),
      body: roleCreateBody(
        name: name,
        description: description,
        groups: groups,
        visibility: visibility,
      ),
    );
  }

  /// The create body, split out so the contract is testable without a socket.
  ///
  /// One `module_groups` entry per checked card, each carrying the form's
  /// single visibility choice — the shape `roles.md` §3 documents as the
  /// recommended (group-based) input. This used to be hard-coded to
  /// `[{group: crm, visibility: hierarchy}]`, so every role came out granting
  /// CRM at hierarchy scope no matter what the form was set to.
  ///
  /// With nothing checked the key is omitted rather than sent empty: the server
  /// treats a supplied `module_groups` as the **complete** grant set, and `[]`
  /// would be an explicit "grant nothing".
  static Map<String, dynamic> roleCreateBody({
    required String name,
    String? description,
    Set<String> groups = const {},
    String visibility = 'hierarchy',
  }) {
    return {
      'name': name.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (groups.isNotEmpty)
        'module_groups': [
          for (final group in groups) {'group': group, 'visibility': visibility},
        ],
    };
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

  /// A member row → `active` | `inactive` | `invited`.
  ///
  /// There is no status field on the backend (`members.md` §Status): everything
  /// hangs off `is_active`, and the two false cases are told apart client-side
  /// by whether the user has ever logged in. Someone an admin deactivated has
  /// a last-login; someone still sitting on an unopened activation email does
  /// not.
  ///
  /// This used to answer `is_active ? active : invited`, which labelled every
  /// deactivated member "Invited" — and left the drawer's Inactive chip matching
  /// nothing, since the value was never produced.
  static String memberStatusKey(Map<String, dynamic> json) {
    if (json['is_active'] == true) return 'active';
    // `last_login` is the reliable signal; `date_joined`-style keys are not, as
    // an invited user has those too.
    final lastLogin = json['last_login'];
    final hasLoggedIn = lastLogin != null && '$lastLogin'.trim().isNotEmpty;
    return hasLoggedIn ? 'inactive' : 'invited';
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
    var designation = '';
    var timezone = '';
    if (profile is Map) {
      phone = (profile['phone'] as String?) ?? '';
      if (phone.isEmpty) phone = (profile['mobile'] as String?) ?? '';
      designation = (profile['designation'] as String? ?? '').trim();
      timezone = (profile['timezone'] as String? ?? '').trim();
    }

    // Territories this user *manages*; absent on list rows.
    final territoriesRaw = json['territories'];
    final territories = <String>[
      if (territoriesRaw is List)
        for (final t in territoriesRaw)
          if (t is Map && (t['name'] as String? ?? '').trim().isNotEmpty)
            (t['name'] as String).trim(),
    ];

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
      managerId: manager is Map ? (manager['user_id'] as String? ?? '') : '',
      team: team,
      status: memberStatusKey(json),
      designation: designation,
      timezone: timezone,
      territories: territories,
      isProtected: json['is_protected'] == true,
    );
  }

  /// One activity row → [MemberActivity]. Returns null when the row carries no
  /// label, which is the only field the card cannot render without.
  static MemberActivity? activityFromJson(Map<String, dynamic> json) {
    final label = (json['label'] as String? ?? '').trim();
    if (label.isEmpty) return null;
    final actor = json['actor'];
    return MemberActivity(
      type: (json['type'] as String? ?? '').trim(),
      label: label,
      // `actor` is a display name on this feed, not the nested user object the
      // CRM endpoints send.
      actor: actor is String ? actor.trim() : '',
      at: parseApiDate(json['timestamp']),
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
      managerId: m.managerId,
      team: m.team,
      status: m.status,
      // Carried through, or overlaying performance would blank the detail
      // fields the retrieve call had just filled in.
      designation: m.designation,
      timezone: m.timezone,
      territories: m.territories,
      isProtected: m.isProtected,
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
    final groupKeys = <String>[];
    final grouped = json['grouped_permissions'];
    if (grouped is List) {
      for (final group in grouped) {
        if (group is Map && group['group'] is String) {
          final key = (group['group'] as String).trim();
          if (key.isEmpty || groupKeys.contains(key)) continue;
          groupKeys.add(key);
          caps.add(key.toUpperCase());
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
      groupKeys: groupKeys,
      scopeCode: _roleScopeCode(json) ?? '',
      // Absent on an older payload: fall back to "editable implies deletable",
      // which is what the screen assumed before this field existed.
      deletable: json['is_deletable'] as bool? ?? (json['is_editable'] != false),
      userCount: (json['user_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// `permission_type` code → the visibility label the UI renders. Shared with
  /// the Add role form ([kRoleScopeLabels]) so a scope reads the same on the
  /// card that displays it and on the form that sets it.
  static const Map<String, String> _scopeLabels = kRoleScopeLabels;

  /// Derives a role's visibility scope from its lead-module record permission
  /// (the same signal the web app's sub-label uses). Roles with no lead scope
  /// (e.g. the seeded Admin, whose access is the `is_staff` bypass) read as
  /// Organization-wide when they look full-access, `'—'` otherwise.
  static String _roleScope(Map<String, dynamic> json) {
    final label = _scopeLabels[_roleScopeCode(json) ?? ''];
    if (label != null) return label;
    final level = (json['permission_level'] as num?)?.toInt() ?? 0;
    return level >= 100 ? 'Organization-wide' : '—';
  }

  /// The raw `permission_type` behind [_roleScope] — what the edit form needs
  /// to preselect a scope, since the label is not what a write accepts.
  static String? _roleScopeCode(Map<String, dynamic> json) {
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

    return type;
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

  Future<List<Map<String, dynamic>>> _pagedRows(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; page <= _maxPages; page++) {
      final body = await _api.get(path, query: {
        'page': page,
        'page_size': ApiConfig.defaultPageSize,
        ...query,
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
