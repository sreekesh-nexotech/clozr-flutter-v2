import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/lead.dart';
import '../../infrastructure/data_sources/remote/crm_catalog_remote_ds.dart';

/// The org's CRM option lists (pipeline stages, lead sources), used to drive
/// the Leads status tabs and filter drawer from the backend instead of the
/// built-in `StatusMeta$` vocabulary.
///
/// Every provider here degrades to an **empty list** — in mock mode, and on any
/// fetch failure. Empty is the agreed signal for "fall back to `StatusMeta$`",
/// so a backend that is down or a QA build with no API still renders the screen
/// exactly as it did before.

/// Null in mock mode, which is what makes the catalogs resolve empty there.
final crmCatalogRemoteDataSourceProvider =
    Provider<CrmCatalogRemoteDataSource?>((ref) {
  if (!ApiConfig.apiEnabled) return null;
  return CrmCatalogRemoteDataSource(ref.watch(apiServiceProvider));
});

/// `GET /crm/lead-statuses/` — the org's pipeline stages, in server order.
final leadStatusCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  final ds = ref.watch(crmCatalogRemoteDataSourceProvider);
  return ds == null ? const <CatalogOption>[] : ds.fetchLeadStatuses();
});

/// `GET /crm/lead-sources/?is_active=true` — the org's active lead sources.
final leadSourceCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  final ds = ref.watch(crmCatalogRemoteDataSourceProvider);
  return ds == null ? const <CatalogOption>[] : ds.fetchLeadSources();
});

/// `GET /crm/products/` — the org's product catalog, as filter options.
final productCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  final ds = ref.watch(crmCatalogRemoteDataSourceProvider);
  return ds == null ? const <CatalogOption>[] : ds.fetchProducts();
});

/// `GET /management/teams/` — the org's teams, as filter options.
final teamCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  final ds = ref.watch(crmCatalogRemoteDataSourceProvider);
  return ds == null ? const <CatalogOption>[] : ds.fetchTeams();
});

/// `GET /crm/follow-up-types/?is_active=true` — the org's follow-up types.
final followupTypeCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  final ds = ref.watch(crmCatalogRemoteDataSourceProvider);
  return ds == null ? const <CatalogOption>[] : ds.fetchFollowupTypes();
});

/// `GET /crm/task-priorities/?is_active=true` — the org's task priorities.
final taskPriorityCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  final ds = ref.watch(crmCatalogRemoteDataSourceProvider);
  return ds == null ? const <CatalogOption>[] : ds.fetchTaskPriorities();
});

/// `GET /crm/crm-task-statuses/` — the org's task statuses, with status types.
final taskStatusCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  final ds = ref.watch(crmCatalogRemoteDataSourceProvider);
  return ds == null ? const <CatalogOption>[] : ds.fetchTaskStatuses();
});

/// The task types, read out of `GET /crm/tasks/schema/?view_type=form` — they
/// are model choices, not an org catalog, so they have no list endpoint.
final taskTypeCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  final ds = ref.watch(crmCatalogRemoteDataSourceProvider);
  return ds == null ? const <CatalogOption>[] : ds.fetchTaskTypes();
});

/// `GET /crm/territories/` — the org's territories, for the lead form.
final territoryCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  final ds = ref.watch(crmCatalogRemoteDataSourceProvider);
  return ds == null ? const <CatalogOption>[] : ds.fetchTerritories();
});

/// `GET /crm/industries/` — the org's industries, for the lead form.
final industryCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  final ds = ref.watch(crmCatalogRemoteDataSourceProvider);
  return ds == null ? const <CatalogOption>[] : ds.fetchIndustries();
});

/// Synchronous view of [territoryCatalogProvider].
final territoryOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(territoryCatalogProvider).valueOrNull ?? const [],
);

/// Synchronous view of [industryCatalogProvider].
final industryOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(industryCatalogProvider).valueOrNull ?? const [],
);

/// Synchronous view of [leadStatusCatalogProvider] — empty while in flight, so
/// the tabs render immediately from `StatusMeta$` and swap to the org's stages
/// when the catalog arrives, instead of blocking the list behind a spinner.
final leadStatusesProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(leadStatusCatalogProvider).valueOrNull ?? const [],
);

/// Synchronous view of [leadSourceCatalogProvider]. Same empty-while-loading
/// contract as [leadStatusesProvider].
final leadSourcesProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(leadSourceCatalogProvider).valueOrNull ?? const [],
);

/// Synchronous view of [productCatalogProvider]. Same empty-while-loading
/// contract as [leadStatusesProvider].
final productOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(productCatalogProvider).valueOrNull ?? const [],
);

/// Synchronous view of [teamCatalogProvider]. Same empty-while-loading
/// contract as [leadStatusesProvider].
final teamOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(teamCatalogProvider).valueOrNull ?? const [],
);

/// Synchronous view of [followupTypeCatalogProvider]. Empty while loading, in
/// mock mode, and on failure — the Follow-ups drawer and the Add follow-up
/// sheet then fall back to the built-in type list.
final followupTypeOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(followupTypeCatalogProvider).valueOrNull ?? const [],
);

/// Synchronous view of [taskTypeCatalogProvider]. Same empty-means-fall-back
/// contract as [followupTypeOptionsProvider].
final taskTypeOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(taskTypeCatalogProvider).valueOrNull ?? const [],
);

/// Synchronous view of [taskPriorityCatalogProvider].
final taskPriorityOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(taskPriorityCatalogProvider).valueOrNull ?? const [],
);

/// Synchronous view of [taskStatusCatalogProvider].
final taskStatusOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(taskStatusCatalogProvider).valueOrNull ?? const [],
);

/// Completes once **every** option catalog the Leads filter drawer needs has
/// resolved.
///
/// Two jobs. Watching it from the Leads screen starts all four fetches when the
/// screen mounts rather than when the drawer opens — the catalogs are only
/// referenced by the filter spec, so without this they would not even begin
/// loading until the user taps Filter. And awaiting it before building the
/// drawer spec removes the ambiguity in an empty catalog: once this completes,
/// empty means *the org has none*, never *it has not arrived*.
///
/// Never fails: the catalog fetches turn errors into empty lists by design, so
/// this resolves even with the backend down.
final leadFilterCatalogsProvider = FutureProvider<void>((ref) async {
  await Future.wait([
    ref.watch(leadStatusCatalogProvider.future),
    ref.watch(leadSourceCatalogProvider.future),
    ref.watch(productCatalogProvider.future),
    ref.watch(teamCatalogProvider.future),
  ]);
});

/// The dot/pill colour for an org task lane, on the same terms as
/// [leadStatusColor]: the admin's own colour when set, else the built-in
/// colour of the bucket the lane folds into.
Color crmTaskStatusColor(CatalogOption status) =>
    status.color ??
    StatusMeta$.task[crmTaskStatusKey(name: status.name, type: status.statusType)]!
        .color;

/// The pill a task's status should render as — the twin of [leadStatusMeta].
///
/// Shows the org's **own** lane name whenever the API sent one, so a task in
/// "Open" reads "Open" rather than being folded into the built-in "To do", and
/// always agrees with the tab it sits under. Mock rows carry no status name and
/// keep the built-in vocabulary.
StatusMeta crmTaskStatusMeta(CrmTask task, List<CatalogOption> statuses) {
  final name = task.statusName.trim();
  if (name.isEmpty) return StatusMeta$.task[task.status] ?? StatusMeta$.task['todo']!;

  final key = name.toLowerCase();
  for (final s in statuses) {
    if (s.name.trim().toLowerCase() == key) {
      return StatusMeta(s.name, crmTaskStatusColor(s));
    }
  }
  // Catalog still loading, fetch failed, or the lane was removed since this
  // task was written: keep the org's own name, colour it by its bucket.
  final fallback = StatusMeta$.task[task.status] ?? StatusMeta$.task['todo']!;
  return StatusMeta(name, fallback.color);
}

/// The dot/pill colour for an org stage: the admin's own `color` when set,
/// else the built-in colour of the bucket the stage maps into — so a stage
/// created without a colour still reads as won/lost/junk rather than blank.
Color leadStatusColor(CatalogOption status) =>
    status.color ??
    StatusMeta$.lead[leadStatusKey(name: status.name, type: status.statusType)]!
        .color;

/// The pill a lead's status should render as.
///
/// Whenever the API named the stage, the pill shows **that** name — so a lead
/// in "Contacted" reads "Contacted" rather than being folded into the built-in
/// "Qualified", and always agrees with the tab it sits under. The colour comes
/// from the org catalog when it knows the stage, else from the bucket the name
/// folds into. Only mock leads, which carry no status name, use `StatusMeta$`
/// for the label too.
StatusMeta leadStatusMeta(Lead lead, List<CatalogOption> statuses) {
  final name = lead.statusName.trim();
  if (name.isEmpty) return StatusMeta$.lead[lead.status] ?? StatusMeta$.lead['new']!;

  final key = name.toLowerCase();
  for (final s in statuses) {
    if (s.key == key) return StatusMeta(s.name, leadStatusColor(s));
  }
  // Catalog still loading, fetch failed, or the stage was removed since this
  // lead was written: keep the org's own name, colour it by its bucket.
  final fallback = StatusMeta$.lead[lead.status] ?? StatusMeta$.lead['new']!;
  return StatusMeta(name, fallback.color);
}

/// The pill a follow-up's status should render as.
///
/// Follow-ups are Tasks, so their statuses are the org's own `CRMTaskStatus`
/// set — Open / In Progress / Completed / Cancelled by default. Whenever the
/// API named the status, the pill shows **that** name, so a follow-up in
/// "In Progress" reads "In Progress" and agrees with the tab it sits under.
///
/// Only rows carrying no status name — mock mode, or a follow-up the org never
/// set one on — fall back to the built-in Overdue / Upcoming / Done buckets.
/// That fallback used to be the *only* thing rendered, which is why the real
/// statuses never appeared on the card or the detail page.
StatusMeta followupStatusMeta(Followup fu, List<CatalogOption> statuses) {
  final name = fu.statusName.trim();
  final fallback =
      StatusMeta$.followup[fu.status] ?? StatusMeta$.followup['due']!;
  if (name.isEmpty) return fallback;

  final key = name.toLowerCase();
  for (final s in statuses) {
    if (s.key == key) return StatusMeta(s.name, s.color ?? fallback.color);
  }
  // Catalog still loading, fetch failed, or the status was removed since this
  // follow-up was written: keep the org's own name, colour it by its bucket.
  return StatusMeta(name, fallback.color);
}
