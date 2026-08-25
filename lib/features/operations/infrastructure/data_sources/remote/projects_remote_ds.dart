import 'package:dio/dio.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../crm/domain/entities/crm_catalog.dart';
import '../../../../crm/infrastructure/data_sources/remote/crm_catalog_remote_ds.dart' show hexColor;
import '../../../../crm/infrastructure/data_sources/remote/attachments_remote_ds.dart';
import '../../../../crm/domain/entities/lead_file.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/app_error.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/project.dart';

/// Remote source for Operations projects: HTTP + JSON→entity mapping only.
///
/// List reads use the fixed `?view=list` 19-field slim projection
/// (operations.md §1). Slim rows carry no `assignees`, `estimated_costing`,
/// `visibility`, `percent_complete_method` or `description`, so those entity
/// fields fall back to safe display defaults.
class ProjectsRemoteDataSource {
  const ProjectsRemoteDataSource(this._api);

  final ApiService _api;

  static const int _pageSize = 100;
  static const int _maxPages = 50; // safety cap; loop still breaks when next == null

  /// All projects visible to the caller — slim rows, up to 3 pages of 100.
  /// The org's project statuses (`operations.md` §3) and types (§4), for the
  /// tab strip and the drawer's facets.
  ///
  /// Inactive rows are dropped: the doc says to hide `is_active: false` from the
  /// facet, and a status nobody can be in is not worth a chip either.
  ///
  /// Best-effort — a failure yields the empty list, which every caller reads as
  /// "no catalog, use the built-in vocabulary".
  Future<List<CatalogOption>> fetchProjectStatuses() =>
      _facet(ApiEndpoints.projectStatuses, 'project_status_id');

  /// The org's project types.
  ///
  /// A type row names itself in **`project_type`**, not `name`
  /// (`{"project_type_id": "…", "project_type": "Internal"}`) — reading only
  /// `name` dropped every row, so the catalog came back empty. That is not a
  /// quiet degradation: with no catalog the filter codec passes the drawer's
  /// option through unresolved, so picking a type sent
  /// `project_type__in=Internal` and the list answered
  /// `400 "Internal is not a valid value."`
  Future<List<CatalogOption>> fetchProjectTypes() => _facet(
        ApiEndpoints.projectTypes,
        'project_type_id',
        nameKeys: const ['project_type', 'name', 'type_name'],
      );

  Future<List<CatalogOption>> _facet(
    String path,
    String idKey, {
    List<String> nameKeys = const ['name'],
  }) async {
    try {
      final body = await _api.get(path, query: {'page_size': 100});
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      final out = <CatalogOption>[];
      for (final row in rows) {
        if (row['is_active'] == false) continue;
        final id = (row[idKey] ?? '').toString();
        var name = '';
        for (final key in nameKeys) {
          name = (row[key] ?? '').toString().trim();
          if (name.isNotEmpty) break;
        }
        if (id.isEmpty || name.isEmpty) continue;
        // The org's own dot colour, so the status pill and the picker agree
        // with the tab strip instead of falling back to the built-in palette.
        out.add(CatalogOption(id: id, name: name, color: hexColor(row['color'])));
      }
      return out;
    } on Object {
      return const [];
    }
  }

  /// [filters] are `/projects/projects/` query params from the drawer, the
  /// status tabs and the My-projects toggle — applied **server-side**, so
  /// `is not` means "not, anywhere in the org".
  Future<List<Project>> fetchProjects({
    Map<String, dynamic> filters = const {},
  }) async {
    final out = <Project>[];
    for (var page = 1; page <= _maxPages; page++) {
      final body = await _api.get(ApiEndpoints.projects, query: {
        // Paging steers the walk itself, so a stored filter can never own it.
        ...{...filters}..removeWhere((k, _) => k == 'page' || k == 'page_size'),
        'view': 'list',
        'page_size': _pageSize,
        if (page > 1) 'page': page,
      });
      final paged = Paginated.fromAny<Project?>(body, mapProject);
      out.addAll(paged.results.whereType<Project>());
      if (!paged.hasMore) break;
    }
    return out;
  }

  /// `POST /projects/projects/` with the non-empty subset of [fields].
  /// Returns the created project mapped through [mapProject] (null when the
  /// response row is unusable — callers treat that as "refetch the list").
  Future<Project?> createProject(Map<String, dynamic> fields) async {
    final body = await _api.post(ApiEndpoints.projects, body: _clean(fields));
    return body is Map<String, dynamic> ? mapProject(body) : null;
  }

  /// `PATCH /projects/projects/{id}/` with the non-empty subset of [fields].
  Future<void> updateProject(String id, Map<String, dynamic> fields) =>
      _api.patch(ApiEndpoints.project(id), body: _clean(fields));

  /// `POST /projects/projects/{project_id}/archive/` — archive or restore.
  ///
  /// A toggle: `is_archive: false` unarchives. Errors are **not** swallowed —
  /// restoring into a name another active project has taken comes back as
  /// `400 {"errors": {"project_name": …}}`, and the user needs to read that
  /// rather than watch the action quietly do nothing (`operations.md` §8, the
  /// duplicate-name note).
  Future<void> archiveProject(String id, {required bool archive}) =>
      _api.post(ApiEndpoints.projectArchive(id), body: {'is_archive': archive});

  /// `GET /projects/projects/{project_id}/` — one project, **full shape**.
  ///
  /// Worth its own call because the list is fetched with `?view=list`, whose
  /// slim rows drop exactly what the detail page shows: the costing totals, the
  /// nested `assignees`, `assigned_team_name`, `visibility` and
  /// `percent_complete_method` (`operations.md` §1, the `view` param).
  ///
  /// Best-effort — the screen already has the list row to fall back on, so a
  /// failure costs the enrichment rather than the page.
  Future<Project?> fetchProject(String id) async {
    if (id.isEmpty) return null;
    try {
      final body = await _api.get(ApiEndpoints.project(id));
      return body is Map<String, dynamic> ? mapProject(body) : null;
    } on AppError {
      return null;
    }
  }

  /// `GET /projects/project-attachments/?project={id}` — the Files tab (§15).
  ///
  /// Scoped server-side: the doc notes the `project` filter was once missing and
  /// the endpoint returned the whole org's attachments, so sending it matters.
  ///
  /// Rows share the CRM attachment shape, so [AttachmentsRemoteDataSource]'s
  /// mapper is reused rather than duplicated — one place decides what a stored
  /// file looks like.
  Future<List<LeadFile>> fetchProjectAttachments(String projectId) async {
    if (projectId.isEmpty) return const [];
    try {
      final body = await _api.get(ApiEndpoints.projectAttachments,
          query: {'project': projectId, 'page_size': 100});
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      return [
        for (final row in rows)
          if (AttachmentsRemoteDataSource.fileFromJson(row) case final f?) f,
      ];
    } on Object {
      return const [];
    }
  }

  /// `POST /projects/project-attachments/` (multipart) — the Files tab's
  /// upload (§15).
  ///
  /// The doc gives the body as `{project, file_upload}`; the serializer also
  /// requires **`name`**, and answers
  /// `400 {"name": ["This field is required."]}` without it — verified against
  /// the dev backend, where the filename is what the Files list then shows.
  Future<void> uploadProjectAttachment({
    required String projectId,
    required String path,
    required String name,
  }) async {
    final form = FormData.fromMap({
      'project': projectId,
      'name': name,
      'file_upload': await MultipartFile.fromFile(path, filename: name),
    });
    await _api.postForm(ApiEndpoints.projectAttachments, form);
  }

  // ── mapping ──

  /// `?view=list` slim row (or a full row — create/detail responses share the
  /// field names; `manager` may be a bare user-id string or a nested object)
  /// → [Project]. Returns null for rows without a `project_id`; every other
  /// field degrades to a safe default instead of throwing.
  ///
  /// Per-status tab counts (`operations.md` §2), under the same [filters] as
  /// the list. The server strips the status facet itself, so selecting a tab
  /// never zeroes the others.
  ///
  /// Returns `('all' → total, '<status name>' → count)`. Best-effort: a failure
  /// yields an empty map, which the caller reads as "count locally".
  Future<Map<String, int>> fetchStatusCounts(Map<String, dynamic> filters) async {
    try {
      final body = await _api.get(ApiEndpoints.projectStatusCounts, query: {
        // Paging and the status facet are meaningless here; the server ignores
        // the latter anyway, but sending it invites confusion.
        ...{...filters}..removeWhere((k, _) =>
            k == 'page' ||
            k == 'page_size' ||
            k == 'status' ||
            k.startsWith('status__') ||
            k.startsWith('status_name')),
      });
      if (body is! Map) return const {};
      final out = <String, int>{'all': _count(body['total'])};
      for (final row in (body['statuses'] as List? ?? const [])) {
        if (row is! Map) continue;
        final name = (row['name'] ?? '').toString();
        if (name.isEmpty) continue;
        out[name] = _count(row['count']);
      }
      return out;
    } on Object {
      return const {};
    }
  }

  static int _count(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  /// `Project.id` is ALWAYS the `project_id` UUID (never `naming_series`):
  /// ops-task rows reference their project by that UUID, and the UI treats
  /// the id as opaque, displaying `name` instead.
  static Project? mapProject(Map<String, dynamic> row) {
    final id = row['project_id'] as String? ?? '';
    if (id.isEmpty) return null;

    return Project(
      id: id,
      code: (row['naming_series'] as String? ?? '').trim(),
      isOverdue: row['is_overdue'] is bool ? row['is_overdue'] as bool : null,
      name: row['project_name'] as String? ?? '',
      type: row['project_type_name'] as String? ?? '',
      company: row['customer_name'] as String?,
      internal: row['customer'] == null,
      status: projectStatusKey(name: row['status_name'] as String?),
      statusName: (row['status_name'] as String? ?? '').trim(),
      statusId: (row['status'] as String? ?? '').trim(),
      pri: priorityKey(row['priority'] as String?),
      progress: parseAmount(row['percent_complete']).round().clamp(0, 100).toInt(),
      manager: _managerId(row),
      // The five below are **detail-only**: `?view=list` drops the costing
      // totals and the nested `assignees`, so they stay at their defaults on a
      // list row and fill in from `GET /projects/projects/{id}/`. Visibility
      // and progress method used to be the hardcoded "Team" / "Task-based"
      // regardless of what the project actually was.
      assignees: _assignees(row),
      myTask: false,
      start: absoluteDate(parseApiDate(row['expected_start_date'])),
      end: absoluteDate(parseApiDate(row['expected_end_date'])),
      endISO: row['expected_end_date'] as String? ?? '',
      cost: _cost(row),
      costNum: parseAmount(row['estimated_costing']),
      visibility: _titleCase(row['visibility'] as String?),
      method: (row['percent_complete_method'] as String? ?? '').trim(),
      team: (row['assigned_team_name'] as String? ?? '').trim(),
      isArchived: row['is_archived'] == true,
      desc: row['description'] as String? ?? '',
    );
  }

  /// The full row's nested assignee objects, registered so avatars and names
  /// resolve. Empty on a slim row, which omits them entirely.
  static List<String> _assignees(Map<String, dynamic> row) {
    final raw = row['assignees'];
    if (raw is! List) return const [];
    final out = <String>[];
    for (final a in raw) {
      if (a is! Map) continue;
      UserDirectory.registerJson(a);
      final id = UserDirectory.mapUserId(a['user_id'] as String?);
      if (id.isNotEmpty) out.add(id);
    }
    return out;
  }

  /// `estimated_costing` as a display amount. Absent on slim rows, and a real
  /// zero is shown as blank rather than "₹0" — an unset budget is not ₹0.
  static String _cost(Map<String, dynamic> row) {
    if (!row.containsKey('estimated_costing')) return '';
    final value = parseAmount(row['estimated_costing']);
    return value > 0 ? formatInr(value) : '';
  }

  /// `visibility` is a lowercase enum on the wire (`private` / `team` /
  /// `organization`); the Details tab shows it capitalised.
  static String _titleCase(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1);
  }

  /// `manager` is a bare `user_id` string on `?view=list` rows and a nested
  /// user object on full rows — normalize both through
  /// [UserDirectory.mapUserId], registering the name so avatars resolve.
  static String _managerId(Map<String, dynamic> row) {
    final manager = row['manager'];
    if (manager is Map) {
      UserDirectory.registerJson(manager);
      return UserDirectory.mapUserId(manager['user_id'] as String?);
    }
    final id = manager is String ? manager : '';
    final name = row['manager_name'] as String? ?? '';
    if (id.isNotEmpty && name.isNotEmpty) {
      UserDirectory.register(userId: id, fullName: name);
    }
    return UserDirectory.mapUserId(id);
  }

  /// Drops null / empty-string values so POST/PATCH bodies only carry real
  /// user input.
  static Map<String, dynamic> _clean(Map<String, dynamic> fields) => {
        for (final e in fields.entries)
          if (e.value != null && (e.value is! String || (e.value as String).isNotEmpty)) e.key: e.value,
      };
}
