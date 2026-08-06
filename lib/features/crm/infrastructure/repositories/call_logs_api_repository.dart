import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/call_log.dart';
import '../../domain/repositories/call_logs_repository.dart';
import '../data_sources/remote/call_logs_remote_ds.dart';

/// API-backed [CallLogsRepository]. Reads cache the raw rows per lead so a
/// previously-opened lead still shows its calls offline.
class CallLogsApiRepository implements CallLogsRepository {
  const CallLogsApiRepository(this._remote);

  final CallLogsRemoteDataSource _remote;

  static String _cacheKey(String leadId) => 'call_logs_rows_lead_$leadId';

  @override
  Future<List<CallLog>> getCallLogsForLead(String leadId) async {
    final key = _cacheKey(leadId);
    try {
      final rows = await _remote.fetchCallLogRowsForLead(leadId);
      await AppCache.put(AppCache.crmCache, key, rows);
      return CallLogsRemoteDataSource.mapRows(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final data = AppCache.get(AppCache.crmCache, key)?.data;
        if (data is List) {
          return CallLogsRemoteDataSource.mapRows([
            for (final row in data)
              if (row is Map) Map<String, dynamic>.from(row),
          ]);
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> logOutgoingCall({
    required String leadId,
    required String fromNumber,
    required String toNumber,
  }) async {
    await _remote.createOutgoingCall(
      leadId: leadId,
      fromNumber: fromNumber,
      toNumber: toNumber,
    );
    // The lead's call list just changed; drop the cached rows so reopening it
    // offline does not show a history missing the call just placed.
    await AppCache.remove(AppCache.crmCache, _cacheKey(leadId));
  }

  @override
  Future<void> logManualCall({
    required String leadId,
    required String fromNumber,
    required String toNumber,
    required bool incoming,
    required bool isMissed,
    Duration? duration,
    DateTime? startTime,
  }) async {
    await _remote.createManualCall(
      leadId: leadId,
      fromNumber: fromNumber,
      toNumber: toNumber,
      incoming: incoming,
      isMissed: isMissed,
      duration: duration,
      startTime: startTime,
    );
    await AppCache.remove(AppCache.crmCache, _cacheKey(leadId));
  }
}
