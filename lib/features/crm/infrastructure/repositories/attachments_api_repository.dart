import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/lead_file.dart';
import '../../domain/repositories/attachments_repository.dart';
import '../data_sources/remote/attachments_remote_ds.dart';

/// API-backed [AttachmentsRepository]. Reads cache the raw rows per lead so a
/// previously-opened lead still lists its files offline.
class AttachmentsApiRepository implements AttachmentsRepository {
  const AttachmentsApiRepository(this._remote);

  final AttachmentsRemoteDataSource _remote;

  static String _cacheKey(String leadId) => 'attachments_rows_lead_$leadId';

  @override
  Future<List<LeadFile>> getFilesForLead(String leadId) async {
    final key = _cacheKey(leadId);
    try {
      final rows = await _remote.fetchFileRowsForLead(leadId);
      await AppCache.put(AppCache.crmCache, key, rows);
      return AttachmentsRemoteDataSource.mapRows(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final data = AppCache.get(AppCache.crmCache, key)?.data;
        if (data is List) {
          return AttachmentsRemoteDataSource.mapRows([
            for (final row in data)
              if (row is Map) Map<String, dynamic>.from(row),
          ]);
        }
      }
      rethrow;
    }
  }
}
