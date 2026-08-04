import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/followup.dart';
import '../../domain/repositories/followups_repository.dart';
import '../data_sources/remote/followups_remote_ds.dart';

/// API-backed [FollowupsRepository]. Reads cache the raw list rows in Hive so
/// the list survives offline restarts; writes go remote-only and drop the
/// cache key so the next read refetches.
class FollowupsApiRepository implements FollowupsRepository {
  FollowupsApiRepository(this._remote);

  final FollowupsRemoteDataSource _remote;

  static const _cacheKey = 'followups_rows';

  @override
  Future<List<Followup>> getFollowups() async {
    try {
      final rows = await _remote.fetchFollowupRows();
      await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      return FollowupsRemoteDataSource.mapRows(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(AppCache.crmCache, _cacheKey);
        final data = cached?.data;
        if (data is List) {
          return FollowupsRemoteDataSource.mapRows([
            for (final row in data)
              if (row is Map) Map<String, dynamic>.from(row),
          ]);
        }
      }
      rethrow;
    }
  }

  @override
  Future<Followup?> createFollowup(Map<String, dynamic> fields) async {
    final created = await _remote.createFollowup(fields);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    return created;
  }

  @override
  Future<void> setFollowupDone(String id, bool done) async {
    await _remote.setFollowupDone(id, done);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
  }
}
