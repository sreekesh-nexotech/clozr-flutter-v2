import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/dashboard_models.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../data_sources/remote/dashboard_remote_ds.dart';

/// API-backed [DashboardRepository]. The remote data source never throws — a
/// failed call nulls its section and the mapper falls back to the neutral
/// [DashboardData.empty] base there (zeros/empties, **never** mock figures).
///
/// - Any section supplied → cache the raw bundle and map it over the empty base.
/// - Every call failed but Hive has a last-good bundle → map that (stale but
///   real) over the empty base.
/// - Every call failed and no cache → **throw** a representative [AppError] so
///   the screen shows an honest error/retry state instead of fabricated data.
class DashboardApiRepository implements DashboardRepository {
  const DashboardApiRepository(this._remote);

  final DashboardRemoteDataSource _remote;

  @override
  Future<DashboardData> getDashboard(
      {String period = 'month', String? teamId, String? userId}) async {
    final base = DashboardData.empty();
    // The member is part of the cache identity: two selections that differ
    // only by member are different bundles.
    final cacheKey = 'sections:$period:${teamId ?? 'all'}:${userId ?? 'all'}';
    final errors = <AppError>[];
    final sections =
        await _remote.fetchSections(
            period: period, teamId: teamId, userId: userId, errors: errors);
    if (sections.values.any((v) => v != null)) {
      await AppCache.put(AppCache.dashboardCache, cacheKey, sections);
      return DashboardRemoteDataSource.mapDashboard(sections, base);
    }
    final cached = AppCache.get(AppCache.dashboardCache, cacheKey)?.data;
    if (cached is Map) {
      return DashboardRemoteDataSource.mapDashboard(
          Map<String, Object?>.from(cached), base);
    }
    throw _representativeError(errors);
  }

  /// Picks the most actionable error to surface. A 403 (no dashboard access /
  /// non-admin) is the common, explainable case, so it wins; otherwise the
  /// first captured error, else a generic fallback.
  AppError _representativeError(List<AppError> errors) {
    if (errors.isEmpty) {
      return const AppError(
        type: AppErrorType.unknown,
        message: "Couldn't load the dashboard. Please try again.",
      );
    }
    for (final e in errors) {
      if (e.type == AppErrorType.forbidden) return e;
    }
    return errors.first;
  }
}
