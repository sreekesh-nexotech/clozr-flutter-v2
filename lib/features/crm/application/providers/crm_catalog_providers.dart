import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/crm_catalog.dart';
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
