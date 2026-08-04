import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/dashboard_models.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../data_sources/local/dashboard_mock_ds.dart';
import '../data_sources/remote/dashboard_remote_ds.dart';

/// API-backed [DashboardRepository]. The remote data source never throws — a
/// failed call nulls its section and the mapper falls back to the seeded mock
/// value there. When *every* call failed (offline, fully forbidden) the last
/// good raw bundle from Hive is mapped instead, else the seeded bundle.
class DashboardApiRepository implements DashboardRepository {
  const DashboardApiRepository(this._remote, [this._seed = const DashboardMockDataSource()]);

  final DashboardRemoteDataSource _remote;
  final DashboardMockDataSource _seed;

  @override
  Future<DashboardData> getDashboard({String period = 'month', String? teamId}) async {
    final base = _seed.load();
    final cacheKey = 'sections:$period:${teamId ?? 'all'}';
    final sections = await _remote.fetchSections(period: period, teamId: teamId);
    if (sections.values.any((v) => v != null)) {
      await AppCache.put(AppCache.dashboardCache, cacheKey, sections);
      return DashboardRemoteDataSource.mapDashboard(sections, base);
    }
    final cached = AppCache.get(AppCache.dashboardCache, cacheKey)?.data;
    if (cached is Map) {
      return DashboardRemoteDataSource.mapDashboard(
          Map<String, Object?>.from(cached), base);
    }
    return base;
  }
}
