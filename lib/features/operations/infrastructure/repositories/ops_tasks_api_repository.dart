import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../../crm/domain/entities/audit_entry.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../domain/entities/ops_task.dart';
import '../../domain/repositories/ops_tasks_repository.dart';
import '../data_sources/remote/ops_tasks_remote_ds.dart';

/// API-backed [OpsTasksRepository] with a Hive fallback: reads serve the last
/// good list when the network is down; writes are remote-only and drop the
/// cached list so the next read refetches fresh data.
class OpsTasksApiRepository implements OpsTasksRepository {
  const OpsTasksApiRepository(this._remote);

  final OpsTasksRemoteDataSource _remote;

  static const String _box = AppCache.operationsCache;
  static const String _key = 'ops_tasks';

  @override
  Future<List<OpsTask>> getOpsTasks({Map<String, dynamic> filters = const {}}) async {
    try {
      final tasks = await _remote.fetchOpsTasks(filters: filters);
      await AppCache.put(_box, _key, [for (final t in tasks) _toJson(t)]);
      return tasks;
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
  Future<OpsTask?> createOpsTask(Map<String, dynamic> fields) async {
    final created = await _remote.createOpsTask(fields);
    await AppCache.remove(_box, _key);
    return created;
  }

  @override
  Future<void> updateOpsTask(String id, Map<String, dynamic> fields) async {
    await _remote.updateOpsTask(id, fields);
    await AppCache.remove(_box, _key);
  }

  // ── cache round-trip ──
  //
  // Remote rows never carry subtasks/notes/colour (slim projection), so only
  // the primitive fields are persisted; the rest rehydrate to the same
  // defaults the mapper uses.

  static Map<String, dynamic> _toJson(OpsTask t) => {
        'id': t.id,
        'subject': t.subject,
        'projId': t.projId,
        'group': t.group,
        'status': t.status,
        // Without these the offline list loses the org's own status names (so
        // the tabs stop matching), the type facet, the blocker badge and the
        // server's overdue verdict.
        'statusName': t.statusName,
        'projectName': t.projectName,
        'groupId': t.groupId,
        'typeId': t.typeId,
        'typeName': t.typeName,
        'code': t.code,
        'subtaskCount': t.subtaskCount,
        'subtaskDoneCount': t.subtaskDoneCount,
        'pendingDeps': t.pendingDeps,
        'isOverdue': t.isOverdue,
        'pri': t.pri,
        'assignees': t.assignees,
        'milestone': t.milestone,
        'start': t.start,
        'startTime': t.startTime,
        'end': t.end,
        'endTime': t.endTime,
        'endISO': t.endISO,
        'expHrs': t.expHrs,
        'progress': t.progress,
        'weight': t.weight,
        'dept': t.dept,
        'desc': t.desc,
      };

  static OpsTask _fromJson(Map row) => OpsTask(
        id: row['id'] as String? ?? '',
        subject: row['subject'] as String? ?? '',
        projId: row['projId'] as String? ?? '',
        group: row['group'] as String? ?? 'No group',
        status: row['status'] as String? ?? 'open',
        statusName: row['statusName'] as String? ?? '',
        projectName: row['projectName'] as String? ?? '',
        groupId: row['groupId'] as String? ?? '',
        typeId: row['typeId'] as String? ?? '',
        typeName: row['typeName'] as String? ?? '',
        code: row['code'] as String? ?? '',
        subtaskCount: (row['subtaskCount'] as num?)?.toInt() ?? 0,
        subtaskDoneCount: (row['subtaskDoneCount'] as num?)?.toInt() ?? 0,
        pendingDeps: (row['pendingDeps'] as num?)?.toInt() ?? 0,
        isOverdue: row['isOverdue'] as bool?,
        pri: row['pri'] as String? ?? 'Medium',
        assignees: [
          for (final a in row['assignees'] as List? ?? const [])
            if (a is String) a
        ],
        milestone: row['milestone'] == true,
        start: row['start'] as String? ?? '',
        startTime: row['startTime'] as String? ?? '',
        end: row['end'] as String? ?? '',
        endTime: row['endTime'] as String? ?? '',
        endISO: row['endISO'] as String? ?? '',
        // Null, not 0/1: the API has no field behind either, and a default here
        // would be indistinguishable from a real value on the detail page.
        expHrs: (row['expHrs'] as num?)?.toDouble(),
        progress: (row['progress'] as num?)?.toInt(),
        weight: (row['weight'] as num?)?.toDouble(),
        dept: row['dept'] as String? ?? '',
        color: OpsTasksRemoteDataSource.neutralTag,
        subtasks: const [],
        waitingOn: const [],
        notes: const [],
        desc: row['desc'] as String? ?? '',
      );

  @override
  Future<List<CatalogOption>> getOpsTaskStatuses() => _remote.fetchOpsTaskStatuses();

  /// Not cached: an aggregate is cheap, and a stale tab strip over a fresh list
  /// is worse than no strip counts at all.
  @override
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters) =>
      _remote.fetchStatusCounts(filters);

  @override
  Future<List<CatalogOption>> getTaskGroups(String projectId) =>
      _remote.fetchTaskGroups(projectId);

  @override
  Future<void> deleteOpsTask(String id) async {
    await _remote.deleteOpsTask(id);
    await AppCache.remove(_box, _key);
  }

  /// Edges change what the list's `pending_dependency_count` says, so the
  /// cached list has to go with them.
  @override
  Future<void> addDependency({required String taskId, required String dependsOn}) async {
    await _remote.addDependency(taskId: taskId, dependsOn: dependsOn);
    await AppCache.remove(_box, _key);
  }

  @override
  Future<void> removeDependency(String edgeId) async {
    await _remote.removeDependency(edgeId);
    await AppCache.remove(_box, _key);
  }

  /// Detail reads are not cached: the full shape exists precisely because the
  /// cached list rows are the slim projection.
  @override
  Future<OpsTask?> getOpsTask(String id) => _remote.fetchOpsTask(id);

  /// Not cached: subtasks are a child list of one task, and the cached blob is
  /// the org-wide slim list.
  @override
  Future<List<Subtask>> getSubtasks(
    String parentId, {
    Set<String> closedStatusIds = const {},
  }) =>
      _remote.fetchSubtasks(parentId, closedStatusIds: closedStatusIds);

  /// A new subtask changes the parent's `subtask_count` and rolled-up progress,
  /// so the cached list goes with it.
  @override
  Future<void> createSubtask({
    required String parentId,
    required String subject,
    String projectId = '',
  }) async {
    await _remote.createSubtask(
        parentId: parentId, subject: subject, projectId: projectId);
    await AppCache.remove(_box, _key);
  }

  @override
  Future<List<AuditEntry>> getTaskActivity(
    String taskId, {
    Map<String, String> statusNames = const {},
  }) =>
      _remote.fetchTaskActivity(taskId, statusNames: statusNames);
}
