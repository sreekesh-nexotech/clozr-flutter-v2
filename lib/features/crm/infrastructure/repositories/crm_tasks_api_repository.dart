import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/entities/view_schema.dart';
import '../../domain/repositories/crm_tasks_repository.dart';
import '../data_sources/remote/crm_tasks_remote_ds.dart';

/// API-backed [CrmTasksRepository]. Reads cache the raw list rows in Hive so
/// the list survives offline restarts; writes go remote-only and drop the
/// cache key so the next read refetches.
class CrmTasksApiRepository implements CrmTasksRepository {
  CrmTasksApiRepository(this._remote);

  final CrmTasksRemoteDataSource _remote;

  static const _cacheKey = 'crm_tasks_rows';

  @override
  Future<List<CrmTask>> getTasks() async {
    // Started first so it overlaps the row fetch; never throws (empty on
    // failure), so it can be awaited on the offline path too.
    final types = _remote.statusTypes();
    try {
      final rows = await _remote.fetchTaskRows();
      await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      return CrmTasksRemoteDataSource.mapRows(rows, statusTypes: await types);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(AppCache.crmCache, _cacheKey);
        final data = cached?.data;
        if (data is List) {
          return CrmTasksRemoteDataSource.mapRows([
            for (final row in data)
              if (row is Map) Map<String, dynamic>.from(row),
          ], statusTypes: await types);
        }
      }
      rethrow;
    }
  }

  @override
  Future<List<CrmTask>> getTasksForLead(String leadId) async {
    final key = '${_cacheKey}_lead_$leadId';
    final types = _remote.statusTypes();
    try {
      final rows = await _remote.fetchTaskRowsForLead(leadId);
      await AppCache.put(AppCache.crmCache, key, rows);
      return CrmTasksRemoteDataSource.mapRows(rows, statusTypes: await types);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final data = AppCache.get(AppCache.crmCache, key)?.data;
        if (data is List) {
          return CrmTasksRemoteDataSource.mapRows([
            for (final row in data)
              if (row is Map) Map<String, dynamic>.from(row),
          ], statusTypes: await types);
        }
      }
      rethrow;
    }
  }

  @override
  Future<ViewSchema> getTaskDetailSchema() => _remote.fetchTaskDetailSchema();

  @override
  Future<ViewSchema> getTaskListSchema() => _remote.fetchListSchema();

  /// The record endpoint, cached per id so an opened task still reads offline.
  @override
  Future<Map<String, dynamic>?> getTaskRow(String id) async {
    final key = 'crm_task_$id';
    try {
      final row = await _remote.fetchTaskRow(id);
      if (row != null) await AppCache.put(AppCache.crmCache, key, row);
      return row;
    } on AppError catch (e) {
      if (e.type != AppErrorType.network && e.type != AppErrorType.timeout) {
        rethrow;
      }
      final cached = AppCache.get(AppCache.crmCache, key)?.data;
      return cached is Map<String, dynamic> ? cached : null;
    }
  }

  @override
  Future<CrmTask?> createTask(Map<String, dynamic> fields) async {
    final created = await _remote.createTask(fields);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    return created;
  }

  @override
  Future<CrmTask?> updateTask(String id, Map<String, dynamic> fields) async {
    final task = await _remote.updateTask(id, fields);
    await _dropCaches(id);
    return task;
  }

  @override
  Future<void> deleteTask(String id) async {
    await _remote.deleteTask(id);
    await _dropCaches(id);
  }

  /// Every cached copy of a task is stale after a write to it — the list rows,
  /// the per-lead lists, and the record itself.
  Future<void> _dropCaches(String id) async {
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    await AppCache.remove(AppCache.crmCache, 'crm_task_$id');
  }

  @override
  Future<void> setTaskStatusByKey(String taskId, String uiStatusKey) async {
    await _remote.setTaskStatusByKey(taskId, uiStatusKey);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
  }
}
