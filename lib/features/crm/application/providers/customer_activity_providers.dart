import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/entities/call_log.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/lead_file.dart';
import '../../domain/repositories/customers_repository.dart';
import '../../infrastructure/data_sources/remote/call_logs_remote_ds.dart';
import '../../infrastructure/data_sources/remote/crm_tasks_remote_ds.dart';
import '../../infrastructure/data_sources/remote/followups_remote_ds.dart';
import '../../infrastructure/data_sources/remote/invoices_remote_ds.dart';
import 'attachments_providers.dart';
import 'audit_log_providers.dart';
import 'customers_providers.dart';
import 'leads_providers.dart';

/// The customer detail page's activity tabs and audit trail.
///
/// Every tab is an **existing** list endpoint scoped to one customer, per
/// `docs-backend/customer.md` §2b.3. Four of them use the shared
/// generic-relation params (`related_to=customer&related_to_id=<id>`); Payments
/// and Leads scope through their own foreign keys.
///
/// Scoped server-side rather than filtered client-side, which is what these tabs
/// used to do: the mapped entities only carry `leadId`, so a customer's tasks
/// were indistinguishable from unrelated ones and the tabs showed whatever
/// happened to share a lead id.
///
/// All are `autoDispose`: a customer opened earlier in the session must not keep
/// refetching in the background.

/// Null in mock mode, which resolves every tab to an empty list.
ApiService? _api(Ref ref) =>
    ApiConfig.apiEnabled ? ref.watch(apiServiceProvider) : null;

// ── Tasks ──

final customerTasksProvider = FutureProvider.autoDispose
    .family<List<CrmTask>, String>((ref, customerId) async {
  final api = _api(ref);
  if (api == null || customerId.isEmpty) return const [];
  final rows = await CrmTasksRemoteDataSource(api)
      .fetchTaskRowsFor(relatedTo: 'customer', relatedToId: customerId);
  return CrmTasksRemoteDataSource.mapRows(rows);
});

// ── Follow-ups ──

final customerFollowupsProvider = FutureProvider.autoDispose
    .family<List<Followup>, String>((ref, customerId) async {
  final api = _api(ref);
  if (api == null || customerId.isEmpty) return const [];
  return FollowupsRemoteDataSource(api)
      .fetchFollowupsFor(relatedTo: 'customer', relatedToId: customerId);
});

// ── Call log ──

final customerCallLogsProvider = FutureProvider.autoDispose
    .family<List<CallLog>, String>((ref, customerId) async {
  final api = _api(ref);
  if (api == null || customerId.isEmpty) return const [];
  return CallLogsRemoteDataSource(api)
      .fetchCallLogsFor(relatedTo: 'customer', relatedToId: customerId);
});

// ── Files ──
//
// The attachments repository is already generic over the relation, so this needs
// no new plumbing.

final customerFilesProvider = FutureProvider.autoDispose
    .family<List<LeadFile>, String>((ref, customerId) {
  if (customerId.isEmpty) return Future.value(const <LeadFile>[]);
  return ref.watch(attachmentsRepositoryProvider).getFiles('customer', customerId);
});

// ── Payments ──
//
// The invoice header, scoped `?customer_id=` — the server walks
// Payment → Quotation → Customer.

final customerInvoicesProvider = FutureProvider.autoDispose
    .family<List<Invoice>, String>((ref, customerId) async {
  final api = _api(ref);
  if (api == null || customerId.isEmpty) return const [];
  final rows = await InvoicesRemoteDataSource(api)
      .fetchInvoiceRows(customerId: customerId);
  return invoicesFromApiRows(rows);
});

// ── Leads ──
//
// `?parent_customer=` returns the **upsell** leads spawned from this customer.
// The original source lead is not a child of it, so it is absent here and shows
// up in the record's own `linked_leads` instead — the docs call this out, and it
// is why the tab is not the whole lifetime of the relationship.

final customerLeadsProvider = FutureProvider.autoDispose
    .family<List<Lead>, String>((ref, customerId) async {
  if (customerId.isEmpty) return const [];
  return ref.watch(leadsRepositoryProvider).getLeads(
        filters: {'parent_customer': customerId},
      );
});

// ── Audit trail ──

/// The activity log for one customer: `?model_name=Customer&record_id=<id>`.
///
/// Depends on the write tick, so **any** successful POST/PUT/PATCH/DELETE the app
/// makes refetches it. That is what keeps this card honest without every action
/// on the page having to remember to invalidate it — a status change, an upsell,
/// a reassignment, a new task, a note, an upload.
final customerActivityLogProvider = FutureProvider.autoDispose
    .family<List<AuditEntry>, String>((ref, customerId) async {
  final ds = ref.watch(auditLogRemoteDataSourceProvider);
  if (ds == null || customerId.isEmpty) return const [];
  ref.watch(apiWriteTickProvider);
  // Resolves a `status_id` in the diff to the status name an admin gave it.
  final statuses = ref.watch(customerStatusesProvider);
  return ds.fetchFor(
    modelName: 'Customer',
    recordId: customerId,
    statusNames: {for (final s in statuses) s.id: s.name},
  );
});

// ── The org's customer statuses ──

final customerStatusCatalogProvider =
    FutureProvider<List<CustomerStatus>>((ref) async {
  return ref.watch(customersRepositoryProvider).getCustomerStatuses();
});

/// Synchronous view — empty while in flight, in mock mode, and on failure, which
/// the status control reads as "fall back to the built-in vocabulary".
final customerStatusesProvider = Provider<List<CustomerStatus>>((ref) =>
    ref.watch(customerStatusCatalogProvider).valueOrNull ?? const []);

// ── Owner override ──

/// The owner this session last successfully wrote, per customer id.
///
/// Needed because `assigned_to` is **not returned** by the customer endpoints:
/// both the list and the retrieve payload are trimmed to the org's
/// list/detail-visible columns, and `assigned_to` is not among them by default —
/// it is absent even from the `PATCH` echo. So a reassignment that the server
/// accepted had nothing to render, and the Owner block sat on "Unknown" forever.
///
/// Read *after* the mapped value, never instead of it (see `_ownerOf` on the
/// detail screen): the moment an admin makes `assigned_to` visible, the payload
/// carries the real owner and this stops being consulted — so it heals itself
/// rather than pinning a stale local guess.
final customerOwnerOverrideProvider =
    StateProvider<Map<String, String>>((ref) => const {});
