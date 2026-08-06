import '../../../../app/config/constants.dart';
import '../../domain/entities/lead_file.dart';
import '../../domain/repositories/attachments_repository.dart';
import '../data_sources/local/attachments_mock_ds.dart';

/// Mock-backed implementation.
class AttachmentsRepositoryImpl implements AttachmentsRepository {
  const AttachmentsRepositoryImpl(this._local);

  final AttachmentsMockDataSource _local;

  @override
  Future<List<LeadFile>> getFilesForLead(String leadId) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchFilesForLead(leadId);
  }
}
