import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/leads_repository.dart';
import '../data_sources/remote/leads_remote_ds.dart';

/// API-backed [LeadsRepository]. Reads cache the raw JSON rows and serve them
/// back when the network is unreachable; writes are remote-only and drop the
/// cached list so the next read refetches.
class LeadsApiRepository implements LeadsRepository {
  const LeadsApiRepository(this._remote);

  final LeadsRemoteDataSource _remote;

  static const String _cacheKey = 'leads';

  @override
  Future<List<Lead>> getLeads() async {
    try {
      final rows = await _remote.fetchLeadRows();
      await AppCache.put(AppCache.crmCache, _cacheKey, rows);
      return LeadsRemoteDataSource.mapLeadRows(rows);
    } on AppError catch (e) {
      if (e.type != AppErrorType.network && e.type != AppErrorType.timeout) {
        rethrow;
      }
      final cached = AppCache.get(AppCache.crmCache, _cacheKey)?.data;
      if (cached is List) return LeadsRemoteDataSource.mapLeadRows(cached);
      rethrow;
    }
  }

  @override
  Future<Lead?> createLead(Map<String, dynamic> fields) async {
    final lead = await _remote.createLead(fields);
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    return lead;
  }
}
