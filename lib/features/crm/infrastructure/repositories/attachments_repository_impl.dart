import '../../../../app/config/constants.dart';
import '../../domain/entities/lead_file.dart';
import '../../domain/repositories/attachments_repository.dart';
import '../data_sources/local/attachments_mock_ds.dart';

/// Mock-backed implementation.
class AttachmentsRepositoryImpl implements AttachmentsRepository {
  const AttachmentsRepositoryImpl(this._local);

  final AttachmentsMockDataSource _local;

  /// The seed only has lead files; any other record reads empty.
  @override
  Future<List<LeadFile>> getFiles(String relatedTo, String relatedToId) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return relatedTo == 'lead' ? _local.fetchFilesForLead(relatedToId) : const [];
  }

  @override
  Future<List<LeadFile>> getFilesForLead(String leadId) =>
      getFiles('lead', leadId);

  /// Mock mode has no CDN to upload to. Returning null keeps the caller honest
  /// — it reports "nothing was stored" rather than claiming a file landed.
  @override
  Future<LeadFile?> uploadFile({
    required String relatedTo,
    required String relatedToId,
    required String path,
    required String name,
    String description = '',
  }) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return null;
  }

  @override
  Future<LeadFile?> uploadFileForLead({
    required String leadId,
    required String path,
    required String name,
    String description = '',
  }) =>
      uploadFile(
          relatedTo: 'lead', relatedToId: leadId, path: path, name: name);
}
