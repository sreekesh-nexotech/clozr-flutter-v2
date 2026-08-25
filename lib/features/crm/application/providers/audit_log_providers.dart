import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/audit_entry.dart';
import '../../infrastructure/data_sources/remote/audit_log_remote_ds.dart';
import 'crm_catalog_providers.dart';
import 'quotes_providers.dart';
import '../../../helpdesk/application/providers/tickets_providers.dart';

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
/// Refetches after **any** successful write the app makes, not just the actions
/// wired to it. The log reflects everything that happens to a lead — a stage
/// change, a call, a task, a note, an upload, an edit — so listing those call
/// sites by hand would go stale the moment a new one was added. Watching the
/// write tick means every POST/PUT/PATCH/DELETE refreshes it for free.
///
/// `autoDispose` matters here: without it, every lead opened this session would
/// still be listening and would refetch on every write anywhere.
final leadActivityLogProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>, String>((ref, leadId) async {
  final ds = ref.watch(auditLogRemoteDataSourceProvider);
  if (ds == null) return const [];
  ref.watch(apiWriteTickProvider);
  final statuses = ref.watch(leadStatusesProvider);
  return ds.fetchFor(
    modelName: 'Lead',
    recordId: leadId,
    statusNames: {for (final s in statuses) s.id: s.name},
  );
});

/// The activity log for one quote:
/// `?model_name=Quotation&record_id=<quotation_id>` (doc §1c's panel table).
///
/// [quotationId] is the record **UUID**, not the `QTN-…` display number — the
/// audit trail keys on the primary key.
///
/// Same write-tick dependency as the lead and task logs: every successful
/// POST/PUT/PATCH/DELETE the app makes refetches it, so a status move, an
/// Accept & invoice, a note or an edit all appear without each call site having
/// to remember to invalidate.
final quoteActivityLogProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>, String>((ref, quotationId) async {
  final ds = ref.watch(auditLogRemoteDataSourceProvider);
  if (ds == null) return const [];
  ref.watch(apiWriteTickProvider);
  // Resolves a `status_id` in the diff to the org's own status name.
  final statuses = ref.watch(quoteStatusOptionsProvider);
  return ds.fetchFor(
    modelName: 'Quotation',
    recordId: quotationId,
    statusNames: {for (final s in statuses) s.id: s.name},
    recordLabel: 'Quote',
  );
});

/// The activity log for one catalog item:
/// `?model_name=Product&record_id=<product_id>`.
///
/// `products.md` documents no per-product activity feed, so this is the
/// org-wide trail every other module's detail page uses (`leads.md` §"Audit
/// log", `customer.md`, the quotation doc's "Audit log (bottom of page)").
/// Verified against the dev backend: a create lands here with the full
/// `request_body` — including the fields the product detail endpoint does not
/// return.
///
/// No status catalog is passed: a product has no status, only `is_active`.
final productActivityLogProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>, String>((ref, productId) async {
  final ds = ref.watch(auditLogRemoteDataSourceProvider);
  if (ds == null || productId.isEmpty) return const [];
  ref.watch(apiWriteTickProvider);
  return ds.fetchFor(
    modelName: 'Product',
    recordId: productId,
    recordLabel: 'Product',
  );
});

/// The activity log for one helpdesk ticket:
/// `?model_name=Issue&record_id=<issue_id>`.
///
/// The ticket detail's trail was **derived client-side** — invented entries
/// ("Assignee changed · Manoj Varma", "Status changed — New → Open") built from
/// the ticket's own fields, naming a prototype user who had done nothing. The
/// backend keeps a real one, SLA events included.
final ticketActivityLogProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>, String>((ref, issueId) async {
  final ds = ref.watch(auditLogRemoteDataSourceProvider);
  if (ds == null) return const [];
  ref.watch(apiWriteTickProvider);
  final statuses = ref.watch(ticketStatusOptionsProvider);
  return ds.fetchFor(
    modelName: 'Issue',
    recordId: issueId,
    statusNames: {for (final s in statuses) s.id: s.name},
    recordLabel: 'Ticket',
  );
});

/// The activity log for one project:
/// `?model_name=Project&record_id=<project_id>`.
///
/// Same write-tick dependency as the others: every successful POST/PUT/PATCH/
/// DELETE refetches it, so a status move, an edit or a note appears without the
/// call sites having to remember.
final projectActivityLogProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>, String>((ref, projectId) async {
  final ds = ref.watch(auditLogRemoteDataSourceProvider);
  if (ds == null) return const [];
  ref.watch(apiWriteTickProvider);
  return ds.fetchFor(modelName: 'Project', recordId: projectId);
});

/// The activity log for one task: `?model_name=Task&record_id=<task_id>`.
///
/// Same write-tick dependency as the lead log — every successful POST/PUT/
/// PATCH/DELETE the app makes refetches it, so an edit, a status change, a note
/// or an upload all show up without each call site having to remember.
final taskActivityLogProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>, String>((ref, taskId) async {
  final ds = ref.watch(auditLogRemoteDataSourceProvider);
  if (ds == null) return const [];
  ref.watch(apiWriteTickProvider);
  // Task statuses resolve a `status_id` in the diff to its display name.
  final statuses = ref.watch(taskStatusOptionsProvider);
  return ds.fetchFor(
    modelName: 'Task',
    recordId: taskId,
    statusNames: {for (final s in statuses) s.id: s.name},
  );
});
