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

  static String _cacheKey(String relatedTo, String relatedToId) =>
      'attachments_rows_${relatedTo}_$relatedToId';

  @override
  Future<List<LeadFile>> getFiles(String relatedTo, String relatedToId) async {
    final key = _cacheKey(relatedTo, relatedToId);
    try {
      final rows = await _remote.fetchFileRows(relatedTo, relatedToId);
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

  @override
  Future<LeadFile?> uploadFile({
    required String relatedTo,
    required String relatedToId,
    required String path,
    required String name,
    String description = '',
  }) async {
    final file = await _remote.uploadFile(
      relatedTo: relatedTo,
      relatedToId: relatedToId,
      path: path,
      name: name,
      description: description,
    );
    // The record's file list is now stale; drop it so the next read refetches.
    await AppCache.remove(AppCache.crmCache, _cacheKey(relatedTo, relatedToId));
    return file;
  }

  // ── lead-scoped wrappers, so the lead screens read as before ──

  @override
  Future<List<LeadFile>> getFilesForLead(String leadId) =>
      getFiles('lead', leadId);

  @override
  Future<LeadFile?> uploadFileForLead({
    required String leadId,
    required String path,
    required String name,
    String description = '',
  }) =>
      uploadFile(
        relatedTo: 'lead',
        relatedToId: leadId,
        path: path,
        name: name,
        description: description,
      );
}
