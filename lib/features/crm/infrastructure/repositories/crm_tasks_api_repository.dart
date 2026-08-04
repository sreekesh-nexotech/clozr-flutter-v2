import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/crm_task.dart';
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
    try {
      final rows = await _remote.fetchTaskRows();
      await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      return CrmTasksRemoteDataSource.mapRows(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(AppCache.crmCache, _cacheKey);
        final data = cached?.data;
        if (data is List) {
          return CrmTasksRemoteDataSource.mapRows([
            for (final row in data)
              if (row is Map) Map<String, dynamic>.from(row),
          ]);
        }
      }
      rethrow;
    }
  }

  @override
  Future<CrmTask?> createTask(Map<String, dynamic> fields) async {
    final created = await _remote.createTask(fields);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    return created;
  }

  @override
  Future<void> setTaskStatusByKey(String taskId, String uiStatusKey) async {
    await _remote.setTaskStatusByKey(taskId, uiStatusKey);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
  }
}
