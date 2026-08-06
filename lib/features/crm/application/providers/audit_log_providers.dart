import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/audit_entry.dart';
import '../../infrastructure/data_sources/remote/audit_log_remote_ds.dart';
import 'crm_catalog_providers.dart';

/// A record's activity log, from the shared audit trail.
///
/// Same contract as the CRM catalogs: **empty is the fallback**, never an
/// error. Mock mode, a failed fetch, and a user without `view_audit_log` (which
/// 403s) all resolve to an empty list, and the card simply does not render.

/// Null in mock mode, which is what makes the log resolve empty there.
final auditLogRemoteDataSourceProvider =
    Provider<AuditLogRemoteDataSource?>((ref) {
  if (!ApiConfig.apiEnabled) return null;
  return AuditLogRemoteDataSource(ref.watch(apiServiceProvider));
});

/// Bumped whenever a record is changed, so anything derived from its audit
/// trail refetches. One counter per record id.
///
/// The activity log is the one card on a detail screen that reflects *every*
/// action rather than one list, so it cannot piggyback on the provider a given
/// action already refreshes. Watching all of them instead would be worse: the
/// tab lists are created lazily, one per open tab, so depending on them would
/// fire a request for every tab the moment the screen opened.
final recordRevisionProvider = StateProvider.family<int, String>((ref, _) => 0);

/// Signals that [recordId] changed. Call after any write that the audit trail
/// would record — a stage change, a call, a task, a note, an upload.
void markRecordChanged(WidgetRef ref, String recordId) {
  if (recordId.isEmpty) return;
  ref.read(recordRevisionProvider(recordId).notifier).update((v) => v + 1);
}

/// The activity log for one lead: `?model_name=Lead&record_id=<lead_id>`.
///
/// The org's stage catalog is passed into the mapper so a status change reads
/// "Status changed to Qualified" — the raw row carries only a `status_id`.
final leadActivityLogProvider =
    FutureProvider.family<List<AuditEntry>, String>((ref, leadId) async {
  final ds = ref.watch(auditLogRemoteDataSourceProvider);
  if (ds == null) return const [];
  // Refetch on every recorded change to this lead.
  ref.watch(recordRevisionProvider(leadId));
  final statuses = ref.watch(leadStatusesProvider);
  return ds.fetchFor(
    modelName: 'Lead',
    recordId: leadId,
    statusNames: {for (final s in statuses) s.id: s.name},
  );
});
