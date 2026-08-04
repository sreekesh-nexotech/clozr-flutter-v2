import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
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
  Future<List<OpsTask>> getOpsTasks() async {
    try {
      final tasks = await _remote.fetchOpsTasks();
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
        expHrs: (row['expHrs'] as num?)?.toInt() ?? 0,
        progress: (row['progress'] as num?)?.toInt(),
        weight: (row['weight'] as num?)?.toInt() ?? 1,
        dept: row['dept'] as String? ?? '',
        color: OpsTasksRemoteDataSource.neutralTag,
        subtasks: const [],
        waitingOn: const [],
        notes: const [],
        desc: row['desc'] as String? ?? '',
      );
}
