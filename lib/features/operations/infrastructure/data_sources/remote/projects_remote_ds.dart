import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
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
  static const int _maxPages = 3;

  /// All projects visible to the caller — slim rows, up to 3 pages of 100.
  Future<List<Project>> fetchProjects() async {
    final out = <Project>[];
    for (var page = 1; page <= _maxPages; page++) {
      final body = await _api.get(ApiEndpoints.projects, query: {
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

  // ── mapping ──

  /// `?view=list` slim row (or a full row — create/detail responses share the
  /// field names; `manager` may be a bare user-id string or a nested object)
  /// → [Project]. Returns null for rows without a `project_id`; every other
  /// field degrades to a safe default instead of throwing.
  ///
  /// `Project.id` is ALWAYS the `project_id` UUID (never `naming_series`):
  /// ops-task rows reference their project by that UUID, and the UI treats
  /// the id as opaque, displaying `name` instead.
  static Project? mapProject(Map<String, dynamic> row) {
    final id = row['project_id'] as String? ?? '';
    if (id.isEmpty) return null;

    return Project(
      id: id,
      name: row['project_name'] as String? ?? '',
      type: row['project_type_name'] as String? ?? '',
      company: row['customer_name'] as String?,
      internal: row['customer'] == null,
      status: projectStatusKey(name: row['status_name'] as String?),
      pri: priorityKey(row['priority'] as String?),
      progress: parseAmount(row['percent_complete']).round().clamp(0, 100).toInt(),
      manager: _managerId(row),
      assignees: const [], // absent on slim rows
      myTask: false,
      start: absoluteDate(parseApiDate(row['expected_start_date'])),
      end: absoluteDate(parseApiDate(row['expected_end_date'])),
      endISO: row['expected_end_date'] as String? ?? '',
      cost: '', // estimated_costing absent on slim rows
      visibility: 'Team',
      method: 'Task-based',
      desc: row['description'] as String? ?? '',
    );
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
