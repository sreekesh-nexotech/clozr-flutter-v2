import '../entities/lead_file.dart';

/// Abstract contract for the shared CRM attachment table.
///
/// Like call logs, attachments are only read per record, so the list is always
/// scoped with `related_to` / `related_to_id`.
abstract class AttachmentsRepository {
  /// Files attached to any record, newest first. The table is polymorphic —
  /// `relatedTo` is `lead` / `task` / `quotation` / ….
  Future<List<LeadFile>> getFiles(String relatedTo, String relatedToId);

  /// Uploads one picked file against any record (`multipart/form-data`).
  Future<LeadFile?> uploadFile({
    required String relatedTo,
    required String relatedToId,
    required String path,
    required String name,
    String description,
  });

  /// Files attached to [leadId], newest first.
  Future<List<LeadFile>> getFilesForLead(String leadId);

  /// Uploads one picked file against [leadId] (`multipart/form-data`).
  ///
  /// Returns the stored attachment, or null when the response carries no
  /// usable row (mock mode always returns null — nothing is persisted).
  Future<LeadFile?> uploadFileForLead({
    required String leadId,
    required String path,
    required String name,
    String description,
  });
}
