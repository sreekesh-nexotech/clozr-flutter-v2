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

/// The activity log for one lead: `?model_name=Lead&record_id=<lead_id>`.
///
/// The org's stage catalog is passed into the mapper so a status change reads
/// "Status changed to Qualified" — the raw row carries only a `status_id`.
final leadActivityLogProvider =
    FutureProvider.family<List<AuditEntry>, String>((ref, leadId) async {
  final ds = ref.watch(auditLogRemoteDataSourceProvider);
  if (ds == null) return const [];
  final statuses = ref.watch(leadStatusesProvider);
  return ds.fetchFor(
    modelName: 'Lead',
    recordId: leadId,
    statusNames: {for (final s in statuses) s.id: s.name},
  );
});
