import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../crm/domain/entities/lead_file.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/projects_repository.dart';
import '../data_sources/remote/projects_remote_ds.dart';

/// API-backed [ProjectsRepository] with a Hive fallback: reads serve the last
/// good list when the network is down; writes are remote-only and drop the
/// cached list so the next read refetches fresh data.
class ProjectsApiRepository implements ProjectsRepository {
  const ProjectsApiRepository(this._remote);

  final ProjectsRemoteDataSource _remote;

  static const String _box = AppCache.operationsCache;
  static const String _key = 'projects';

  @override
  Future<List<Project>> getProjects({Map<String, dynamic> filters = const {}}) async {
    try {
      final projects = await _remote.fetchProjects(filters: filters);
      await AppCache.put(_box, _key, [for (final p in projects) _toJson(p)]);
      return projects;
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(_box, _key)?.data;
        if (cached is List) {
          return [
            for (final row in cached)
              if (row is Map) _fromJson(row)
          ];
        }
      }
      rethrow;
    }
  }

  @override
  Future<Project?> createProject(Map<String, dynamic> fields) async {
    final created = await _remote.createProject(fields);
    await AppCache.remove(_box, _key);
    return created;
  }

  @override
  Future<void> updateProject(String id, Map<String, dynamic> fields) async {
    await _remote.updateProject(id, fields);
    await AppCache.remove(_box, _key);
  }

  @override
  Future<Project?> getProject(String id) => _remote.fetchProject(id);

  @override
  Future<void> uploadProjectAttachment({
    required String projectId,
    required String path,
    required String name,
  }) =>
      _remote.uploadProjectAttachment(
          projectId: projectId, path: path, name: name);

  @override
  Future<List<LeadFile>> getProjectAttachments(String projectId) =>
      _remote.fetchProjectAttachments(projectId);

  @override
  Future<void> archiveProject(String id, {required bool archive}) async {
    await _remote.archiveProject(id, archive: archive);
    // Archived projects drop out of the default list, restored ones come
    // back — the cached rows are wrong either way.
    await AppCache.remove(_box, _key);
  }

  // ── cache round-trip — every entity field is a JSON primitive ──

  static Map<String, dynamic> _toJson(Project p) => {
        'id': p.id,
        'code': p.code,
        'isOverdue': p.isOverdue,
        'name': p.name,
        'type': p.type,
        'company': p.company,
        'internal': p.internal,
        'status': p.status,
        'pri': p.pri,
        'progress': p.progress,
        'manager': p.manager,
        'assignees': p.assignees,
        'myTask': p.myTask,
        'start': p.start,
        'end': p.end,
        'endISO': p.endISO,
        'cost': p.cost,
        'costNum': p.costNum,
        'visibility': p.visibility,
        'method': p.method,
        'team': p.team,
        'isArchived': p.isArchived,
        'statusName': p.statusName,
        'desc': p.desc,
      };

  static Project _fromJson(Map row) => Project(
        id: row['id'] as String? ?? '',
        code: row['code'] as String? ?? '',
        isOverdue: row['isOverdue'] as bool?,
        name: row['name'] as String? ?? '',
        type: row['type'] as String? ?? '',
        company: row['company'] as String?,
        internal: row['internal'] == true,
        status: row['status'] as String? ?? 'active',
        pri: row['pri'] as String? ?? 'Medium',
        progress: (row['progress'] as num?)?.toInt() ?? 0,
        manager: row['manager'] as String? ?? '',
        assignees: [
          for (final a in row['assignees'] as List? ?? const [])
            if (a is String) a
        ],
        myTask: row['myTask'] == true,
        start: row['start'] as String? ?? '',
        end: row['end'] as String? ?? '',
        endISO: row['endISO'] as String? ?? '',
        cost: row['cost'] as String? ?? '',
        costNum: (row['costNum'] as num?)?.toDouble() ?? 0,
        // Empty, not "Team" / "Task-based": the old defaults would put the
        // invented values back on every cached read.
        visibility: row['visibility'] as String? ?? '',
        method: row['method'] as String? ?? '',
        team: row['team'] as String? ?? '',
        isArchived: row['isArchived'] == true,
        statusName: row['statusName'] as String? ?? '',
        desc: row['desc'] as String? ?? '',
      );

  @override
  Future<List<CatalogOption>> getProjectStatuses() => _remote.fetchProjectStatuses();

  @override
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters) =>
      _remote.fetchStatusCounts(filters);

  @override
  Future<List<CatalogOption>> getProjectTypes() => _remote.fetchProjectTypes();
}
