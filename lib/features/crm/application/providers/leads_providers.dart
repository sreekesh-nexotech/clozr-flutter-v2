import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/leads_repository.dart';
import '../../infrastructure/data_sources/local/leads_mock_ds.dart';
import '../../infrastructure/data_sources/remote/leads_remote_ds.dart';
import '../../infrastructure/repositories/leads_api_repository.dart';
import '../../infrastructure/repositories/leads_repository_impl.dart';
import '../../../../core/filters/filter_models.dart';
import '../filters/lead_filter_codec.dart';
import '../filters/leads_filter_spec.dart';
import 'crm_catalog_providers.dart';
import 'saved_filters_providers.dart';

/// DI seam: mock-backed by default; API-backed when a base URL is configured.
final leadsRepositoryProvider = Provider<LeadsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const LeadsRepositoryImpl(LeadsMockDataSource());
  }
  return LeadsApiRepository(
    LeadsRemoteDataSource(
      ref.watch(apiServiceProvider),
      // Reuse the status catalog the tabs already fetch, instead of the data
      // source requesting `/crm/lead-statuses/` a second time for the same
      // `name` → `status_type` map.
      statusTypesLoader: () async {
        final catalog = await ref.read(leadStatusCatalogProvider.future);
        return {
          for (final s in catalog)
            if (s.statusType != null && s.statusType!.isNotEmpty)
              s.key: s.statusType!,
        };
      },
    ),
  );
});

/// One server-side lead query: the ownership scope plus the drawer's filters
/// as `LeadFilter` params.
///
/// Value-equal by content so it can key a provider family — two identical
/// queries share one request and one cached result, and changing any part of
/// the filter is a different key, which is what makes an edit refetch.
@immutable
class LeadListQuery {
  const LeadListQuery({this.mineOnly = false, this.filters = const {}});

  final bool mineOnly;
  final Map<String, dynamic> filters;

  /// Order-independent identity — `{a,b}` and `{b,a}` are the same query.
  String get signature {
    final parts = [for (final e in filters.entries) '${e.key}=${e.value}']..sort();
    return 'mine=$mineOnly|${parts.join('&')}';
  }

  @override
  bool operator ==(Object other) =>
      other is LeadListQuery && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

/// Leads for one query. Switching scope or editing a filter switches which
/// instance is watched, which issues a request rather than re-filtering a list
/// that is already on screen.
final leadsScopedProvider = FutureProvider.family<List<Lead>, LeadListQuery>(
  (ref, q) => ref
      .watch(leadsRepositoryProvider)
      .getLeads(mineOnly: q.mineOnly, filters: q.filters),
);

/// The server params a given drawer state produces.
///
/// Shared by [leadFilterParamsProvider] and by the screen, which needs to build
/// the *next* query key before it applies a filter. Both must agree exactly, or
/// the screen would invalidate a key the list never watches.
Map<String, dynamic> leadFilterParamsFor(FilterValues values, LeadFilterCodec codec) {
  // Mock mode has no query engine behind it — the matcher runs locally there.
  if (!ApiConfig.apiEnabled || values.isEmpty) return const {};
  return codec.encode(values);
}

/// The drawer's filters as server params — the payload that makes `is not`
/// mean "not, anywhere in the org" instead of "not, among the rows we loaded".
final leadFilterParamsProvider = Provider<Map<String, dynamic>>(
  (ref) => leadFilterParamsFor(
    ref.watch(leadFiltersProvider),
    ref.watch(leadFilterCodecProvider),
  ),
);

/// Org-wide leads — the cross-screen lookup source. Tasks, follow-ups and
/// customers resolve a linked lead by id here, and reports aggregate over it,
/// so this deliberately ignores the Leads list's My/All toggle and its drawer
/// filters: narrowing it would blank out links to a colleague's lead.
final leadsProvider = FutureProvider<List<Lead>>(
  (ref) => ref.watch(leadsScopedProvider(const LeadListQuery()).future),
);

/// The Leads list itself: the My/All scope **and** the drawer filters, both
/// resolved by the server.
final leadsListProvider = FutureProvider<List<Lead>>(
  (ref) => ref.watch(
    leadsScopedProvider(LeadListQuery(
      mineOnly: !ref.watch(leadTeamAllProvider),
      filters: ref.watch(leadFilterParamsProvider),
    )).future,
  ),
);

/// The same scope with the drawer filters dropped.
///
/// Backs the drawer's live result preview, which must count against the whole
/// scope: a draft usually *widens* the current selection, and counting inside
/// an already-filtered list could only ever count down.
final leadsUnfilteredQueryProvider = Provider<LeadListQuery>(
  (ref) => LeadListQuery(mineOnly: !ref.watch(leadTeamAllProvider)),
);

/// One lead from the **record** endpoint — the detail screen's source.
///
/// A lead found in the list is not good enough here: the list and record
/// endpoints are trimmed to different field configs, so the list row has no
/// `lead_owner`, `email`, `mobile_no`, `whatsapp_no` or `territory` at all. Only
/// this call returns them.
final leadDetailProvider = FutureProvider.family<Lead?, String>(
  (ref, id) => ref.watch(leadsRepositoryProvider).getLead(id),
);

/// The same record, **unmapped**, for the schema-driven edit form.
///
/// The form renders whichever fields the org configured, so it needs values by
/// field name — something the mapped [Lead] cannot answer, since it exposes a
/// fixed set of properties. Same endpoint as [leadDetailProvider]; the two
/// share the repository's per-id cache entry.
final leadRowProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) {
  if (id.isEmpty) return Future.value(null);
  return ref.watch(leadsRepositoryProvider).getLeadRow(id);
});

/// The already-loaded list row for a lead, if there is one — the seed the
/// detail screen shows while [leadDetailProvider] is in flight, so opening a
/// lead paints instantly instead of flashing a skeleton.
///
/// Reads the **currently displayed** scope rather than the org-wide list on
/// purpose: that is the list the user just tapped through, so it is already in
/// memory. Watching the org-wide one would fire a second full list fetch just
/// to populate a placeholder.
final leadByIdProvider = Provider.family<Lead?, String>((ref, id) {
  final leads = ref.watch(leadsListProvider).valueOrNull;
  if (leads == null) return null;
  for (final l in leads) {
    if (l.id == id) return l;
  }
  return null;
});

// ── List UI state ──

/// Active status tab on the Leads list.
final leadTabProvider = StateProvider<String>((ref) => 'all');

/// Search query on the Leads list.
final leadSearchProvider = StateProvider<String>((ref) => '');

/// Whether the search field is expanded.
final leadSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Whether to show all leads (true) or only mine (false, the default) —
/// the prototype's `teamAll` flag / "My leads" default view.
///
/// This is the scope [leadsListProvider] fetches with; flipping it is a
/// refetch, not a client-side filter.
final leadTeamAllProvider = StateProvider<bool>((ref) => false);

/// The base list before the status tab is applied. The mine/all scope and the
/// drawer filters are already applied by the source ([leadsScopedProvider]) —
/// the server does both in API mode — so nothing is re-filtered here.
///
/// Note this means the tab counts reflect the active drawer filters, since
/// they count over this list. That follows from filtering server-side, and
/// matches how the backend's own Kanban board reports its lane counts.
final leadBaseProvider = Provider<List<Lead>>(
  (ref) => ref.watch(leadsListProvider).valueOrNull ?? const [],
);

/// The rows on screen: the base list narrowed by the active tab and the search
/// box.
///
/// The drawer filters are **not** applied here in API mode — the server already
/// ran them, so [leadBaseProvider] *is* the matching set. Tab and search stay
/// local because they run over that complete result, not over a partial page.
final visibleLeadsProvider = Provider<List<Lead>>((ref) {
  final base = ref.watch(leadBaseProvider);
  final tab = ref.watch(leadTabProvider);
  final q = ref.watch(leadSearchProvider).trim().toLowerCase();

  Iterable<Lead> out = base;
  // A tab tapped before the status catalog resolved can name a stage the org
  // does not have ("Quote sent" vs its own "Proposal Sent"). Ignore a tab that
  // is no longer in the vocabulary instead of silently emptying the list.
  if (tab != 'all' && ref.watch(leadTabsProvider).any((t) => t.id == tab)) {
    out = out.where((l) => l.stageKey == tab);
  }
  // Mock mode has no query engine behind it, so the drawer is matched here.
  if (!ApiConfig.apiEnabled) {
    final filters = ref.watch(leadFiltersProvider);
    if (!filters.isEmpty) out = out.where((l) => leadMatchesFilters(l, filters));
  }
  if (q.isNotEmpty) {
    out = out.where((l) =>
        l.name.toLowerCase().contains(q) ||
        (l.company ?? '').toLowerCase().contains(q) ||
        l.project.toLowerCase().contains(q) ||
        l.id.toLowerCase().contains(q));
  }
  return out.toList();
});

/// Count of leads for a given tab key within [base].
int leadTabCount(List<Lead> base, String key) {
  if (key == 'all') return base.length;
  return base.where((l) => l.stageKey == key).length;
}

/// One status tab on the Leads list — also the shape of a Stage filter option,
/// so the tab row and the drawer can never drift apart.
class LeadTab {
  const LeadTab(this.id, this.label, this.color);

  /// The value the list filters by — matched against [Lead.stageKey].
  final String id;
  final String label;
  final Color? color;
}

/// The stage vocabulary to render, resolved once so the tabs and the Stage
/// filter always agree with what [Lead.stageKey] reports.
///
/// Three tiers, in order:
/// 1. the org's `/crm/lead-statuses/` catalog — names, colours and server order;
/// 2. the distinct stage names the loaded leads carry, when the catalog fetch
///    failed but the rows still name their stage. Only stages that have leads
///    get a tab, which is a real loss, but far better than tier 3's tabs that
///    would match nothing at all;
/// 3. the built-in `StatusMeta$` vocabulary — mock mode, where leads carry no
///    status name.
List<LeadTab> leadStageVocabulary(List<CatalogOption> catalog, List<Lead> leads) {
  if (catalog.isNotEmpty) {
    return [for (final s in catalog) LeadTab(s.key, s.name, leadStatusColor(s))];
  }

  // First spelling of each name wins; the key is what rows join on.
  final names = <String, String>{};
  for (final l in leads) {
    final n = l.statusName.trim();
    if (n.isNotEmpty) names.putIfAbsent(n.toLowerCase(), () => n);
  }
  if (names.isEmpty) {
    return [
      for (final k in StatusMeta$.leadAll)
        LeadTab(k, StatusMeta$.lead[k]!.label, StatusMeta$.lead[k]!.color),
    ];
  }

  // No server `position` to sort by here, so order by the bucket each name
  // folds into — close enough to pipeline order to read correctly.
  final entries = names.entries.toList()
    ..sort((a, b) {
      final ia = StatusMeta$.leadAll.indexOf(leadStatusKey(name: a.value));
      final ib = StatusMeta$.leadAll.indexOf(leadStatusKey(name: b.value));
      return ia != ib ? ia.compareTo(ib) : a.value.compareTo(b.value);
    });
  return [
    for (final e in entries)
      LeadTab(e.key, e.value, StatusMeta$.lead[leadStatusKey(name: e.value)]!.color),
  ];
}

/// The status tab row: `All`, then the org's own pipeline stages with their
/// names and colours straight from `/crm/lead-statuses/`.
final leadTabsProvider = Provider<List<LeadTab>>((ref) => [
      const LeadTab('all', 'All', null),
      ...leadStageVocabulary(
        ref.watch(leadStatusesProvider),
        // The rows currently on screen — the fallback vocabulary (used when the
        // catalog fetch failed) must describe the scope being displayed.
        ref.watch(leadBaseProvider),
      ),
    ]);
