import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/crm_home_models.dart';
import '../data_sources/remote/crm_home_remote_ds.dart';

/// API-backed source for the personal CRM Home dashboard.
///
/// - Any section supplied → cache the raw bundle and map it (empty fallbacks
///   for the sections that failed — **never** the mock literals).
/// - Every call failed but Hive has a last-good bundle → map that.
/// - Every call failed and no cache → throw a representative [AppError] so the
///   screen shows an honest error/retry state instead of fabricated data.
class CrmHomeRepository {
  const CrmHomeRepository(this._remote);

  final CrmHomeRemoteDataSource _remote;

  static const _cacheKey = 'crm_home:own';

  Future<CrmHomeData> getHome() async {
    final errors = <AppError>[];
    final raw = await _remote.fetchSections(errors: errors);
    if (raw.values.any((v) => v != null)) {
      await AppCache.put(AppCache.crmCache, _cacheKey, raw);
      return CrmHomeRemoteDataSource.mapHome(raw);
    }
    final cached = AppCache.get(AppCache.crmCache, _cacheKey)?.data;
    if (cached is Map) {
      return CrmHomeRemoteDataSource.mapHome(Map<String, Object?>.from(cached));
    }
    throw _representativeError(errors);
  }

  AppError _representativeError(List<AppError> errors) {
    if (errors.isEmpty) {
      return const AppError(
        type: AppErrorType.unknown,
        message: "Couldn't load your CRM dashboard. Please try again.",
      );
    }
    for (final e in errors) {
      if (e.type == AppErrorType.forbidden) return e;
    }
    return errors.first;
  }
}
