import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/crm_catalog.dart';
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
  static const String _mineCacheKey = 'leads_mine';

  /// The two ownership scopes are different result sets, so they get separate
  /// cache entries — an offline "My leads" must never be served the org-wide
  /// list, or vice versa.
  static String _keyFor(bool mineOnly) => mineOnly ? _mineCacheKey : _cacheKey;

  /// Every call goes to the network first; the cache is an offline fallback
  /// only, never a shortcut. Toggling My/All therefore always re-queries the
  /// server (row shape is scope-dependent, so a stale list can't be reused).
  @override
  Future<List<Lead>> getLeads({
    bool mineOnly = false,
    Map<String, dynamic> filters = const {},
  }) async {
    final key = _keyFor(mineOnly);
    // Only the unfiltered list is cached. A filtered result is one of countless
    // combinations, so caching it would churn the store for a fallback the user
    // is unlikely to hit again — and serving the wrong combination offline
    // would be worse than serving nothing.
    final cacheable = filters.isEmpty;
    // Started first so it overlaps the row fetch; never throws (empty on
    // failure), so it can be awaited on the offline path too.
    final types = _remote.statusTypes();
    try {
      final rows = await _remote.fetchLeadRows(mineOnly: mineOnly, filters: filters);
      if (cacheable) await AppCache.put(AppCache.crmCache, key, rows);
      return LeadsRemoteDataSource.mapLeadRows(rows, statusTypes: await types);
    } on AppError catch (e) {
      if (e.type != AppErrorType.network && e.type != AppErrorType.timeout) {
        rethrow;
      }
      // A filtered query has no cached counterpart; surface the outage rather
      // than quietly showing an unfiltered list as if it were the result.
      final cached = cacheable ? AppCache.get(AppCache.crmCache, key)?.data : null;
      if (cached is List) {
        // Offline: the catalog call failed too, but a previously cached
        // catalog still applies — otherwise this degrades to name matching.
        return LeadsRemoteDataSource.mapLeadRows(cached, statusTypes: await types);
      }
      rethrow;
    }
  }

  /// `GET /crm/leads/{id}/` — the record, trimmed to the org's **detail** field
  /// config. Cached per id so an opened lead still reads offline.
  @override
  Future<Lead?> getLead(String id) async {
    final key = 'lead_$id';
    final types = _remote.statusTypes();
    try {
      final row = await _remote.fetchLeadRow(id);
      if (row == null) return null;
      await AppCache.put(AppCache.crmCache, key, row);
      return LeadsRemoteDataSource.mapLead(row, statusTypes: await types);
    } on AppError catch (e) {
      if (e.type != AppErrorType.network && e.type != AppErrorType.timeout) {
        rethrow;
      }
      final cached = AppCache.get(AppCache.crmCache, key)?.data;
      if (cached is Map<String, dynamic>) {
        return LeadsRemoteDataSource.mapLead(cached, statusTypes: await types);
      }
      rethrow;
    }
  }

  @override
  Future<Lead?> updateLeadStatus(String leadId, String statusId) async {
    final lead = await _remote.updateLeadStatus(leadId, statusId);
    // The stage is part of both list rows and the record, so every cached copy
    // is now stale — drop them rather than serve the old stage offline.
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    await AppCache.remove(AppCache.crmCache, _mineCacheKey);
    await AppCache.remove(AppCache.crmCache, 'lead_$leadId');
    return lead;
  }

  @override
  Future<List<CatalogOption>> getAssignableUsers(String leadId) =>
      _remote.fetchAssignableUsers(leadId);

  @override
  Future<Lead?> createLead(Map<String, dynamic> fields) async {
    final lead = await _remote.createLead(fields);
    // Both scopes can contain the new lead — drop each so either view refetches.
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    await AppCache.remove(AppCache.crmCache, _mineCacheKey);
    return lead;
  }

  @override
  Future<Map<String, dynamic>?> getLeadRow(String id) async {
    final key = 'lead_$id';
    try {
      final row = await _remote.fetchLeadRow(id);
      if (row != null) await AppCache.put(AppCache.crmCache, key, row);
      return row;
    } on AppError catch (e) {
      if (e.type != AppErrorType.network && e.type != AppErrorType.timeout) {
        rethrow;
      }
      final cached = AppCache.get(AppCache.crmCache, key)?.data;
      if (cached is Map<String, dynamic>) return cached;
      rethrow;
    }
  }

  @override
  Future<Lead?> updateLead(String leadId, Map<String, dynamic> fields) async {
    final lead = await _remote.updateLead(leadId, fields);
    // The edited lead appears in both list scopes and in its own detail cache.
    await AppCache.remove(AppCache.crmCache, _cacheKey);
    await AppCache.remove(AppCache.crmCache, _mineCacheKey);
    await AppCache.remove(AppCache.crmCache, 'lead_$leadId');
    return lead;
  }
}
