import '../entities/lead_file.dart';

/// Abstract contract for the shared CRM attachment table.
///
/// Like call logs, attachments are only read per record, so the list is always
/// scoped with `related_to` / `related_to_id`.
abstract class AttachmentsRepository {
  /// Files attached to [leadId], newest first.
  Future<List<LeadFile>> getFilesForLead(String leadId);
}
