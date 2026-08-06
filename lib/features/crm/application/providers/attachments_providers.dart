import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/lead_file.dart';
import '../../domain/repositories/attachments_repository.dart';
import '../../infrastructure/data_sources/local/attachments_mock_ds.dart';
import '../../infrastructure/data_sources/remote/attachments_remote_ds.dart';
import '../../infrastructure/repositories/attachments_api_repository.dart';
import '../../infrastructure/repositories/attachments_repository_impl.dart';

/// DI seam: API-backed when a base URL is configured, mock seed otherwise.
final attachmentsRepositoryProvider = Provider<AttachmentsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const AttachmentsRepositoryImpl(AttachmentsMockDataSource());
  }
  return AttachmentsApiRepository(
    AttachmentsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Files attached to one lead, newest first — the Files tab on the lead detail
/// screen. Keyed by lead id: `GET /crm/attachments/?related_to=lead&
/// related_to_id=<lead_id>`.
final leadFilesProvider =
    FutureProvider.family<List<LeadFile>, String>((ref, leadId) {
  if (leadId.isEmpty) return Future.value(const <LeadFile>[]);
  return ref.watch(attachmentsRepositoryProvider).getFilesForLead(leadId);
});

/// The files attached to one task — the Files tab on the task detail screen.
///
/// Same polymorphic table as the lead's, tagged `related_to=task`.
final taskFilesProvider =
    FutureProvider.family<List<LeadFile>, String>((ref, taskId) {
  if (taskId.isEmpty) return Future.value(const <LeadFile>[]);
  return ref.watch(attachmentsRepositoryProvider).getFiles('task', taskId);
});
