import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/paginated.dart';
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
import 'server_search_providers.dart';

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

/// The Leads list itself: every lead the caller's role can see, narrowed by the
/// drawer filters on the server — the webapp's list has no "My leads" scope.
final leadsListProvider = FutureProvider<List<Lead>>(
  (ref) => ref.watch(
    leadsScopedProvider(leadListQueryFor(
      ref.watch(leadFilterParamsProvider),
      archived: ref.watch(leadArchivedProvider),
    )).future,
  ),
);

/// The list query for [filters] in the current archived/active view. The
/// webapp's Archived toggle is one more server param (`is_archive=true`) on the
/// same list, so it rides in the filter map and stays part of the identity.
LeadListQuery leadListQueryFor(Map<String, dynamic> filters, {bool archived = false}) =>
    LeadListQuery(filters: {...filters, if (archived) 'is_archive': true});

/// The webapp's "Archived" toggle at the end of the status chips: the list,
/// the chip counts and the search all switch to archived leads only.
final leadArchivedProvider = StateProvider<bool>((ref) => false);

/// The same scope with the drawer filters dropped.
///
/// Backs the drawer's live result preview, which must count against the whole
/// scope: a draft usually *widens* the current selection, and counting inside
/// an already-filtered list could only ever count down.
final leadsUnfilteredQueryProvider = Provider<LeadListQuery>(
  (ref) => leadListQueryFor(const {}, archived: ref.watch(leadArchivedProvider)),
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
/// Who this lead may be reassigned to — `GET /crm/leads/{id}/assignable-users/`.
///
/// Not the org roster: the server filters by record access, so it answers who
/// is eligible for *this* lead. `autoDispose` because the picker is opened
/// rarely and eligibility is the server's answer at that moment — caching it
/// for the session could offer someone since deactivated.
final assignableUsersProvider =
    FutureProvider.autoDispose.family<List<CatalogOption>, String>(
  (ref, leadId) => ref.watch(leadsRepositoryProvider).getAssignableUsers(leadId),
);

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

/// The status chips selected on the Leads list — empty is "All".
///
/// Multi-select like the webapp: chips OR-combine (its `status__in`), "All"
/// clears the set, and [leadOtherTab] ("Other / no status") is exclusive.
final leadTabProvider = StateProvider<Set<String>>((ref) => const {});

/// A single chip pre-selected from elsewhere (the dashboard's stage tiles):
/// `'all'` is the empty selection.
Set<String> leadTabSelection(String tab) => tab == 'all' ? const {} : {tab};

/// The webapp's "Other / no status" chip: leads whose stage is in no lane.
const leadOtherTab = '__other__';

/// Webapp `toggleStatusChip`: All clears, a status toggles (and drops Other),
/// Other is exclusive both ways.
Set<String> toggleLeadTab(Set<String> current, String id) {
  if (id == 'all') return const {};
  if (id == leadOtherTab) return current.contains(leadOtherTab) ? const {} : const {leadOtherTab};
  final next = {...current}..remove(leadOtherTab);
  return next.contains(id) ? (next..remove(id)) : (next..add(id));
}

/// Search query on the Leads list.
final leadSearchProvider = StateProvider<String>((ref) => '');

/// Whether the search field is expanded.
final leadSearchOpenProvider = StateProvider<bool>((ref) => false);

/// The base list before the status tab is applied. The drawer filters are
/// already applied by the source ([leadsScopedProvider]) —
/// the server does both in API mode — so nothing is re-filtered here.
///
/// Note this means the tab counts reflect the active drawer filters, since
/// they count over this list. That follows from filtering server-side, and
/// matches how the backend's own Kanban board reports its lane counts.
final leadBaseProvider = Provider<List<Lead>>(
  (ref) => ref.watch(leadsListProvider).valueOrNull ?? const [],
);

/// [leadBaseProvider] narrowed by the search box — what the tabs count and the
/// list shows.
final leadSearchedProvider = Provider<List<Lead>>((ref) {
  final all = ref.watch(leadBaseProvider);
  final q = ref.watch(leadSearchProvider).trim().toLowerCase();
  if (q.isEmpty) return all;
  // Same `?search=` the webapp sends — the server also matches email, phone and
  // the other columns the card does not carry. Applied to the base so the tab
  // counts follow the search, as on the web.
  final matches = serverSearchMatcher(
    ref,
    ServerSearchKey(
      endpoint: ApiEndpoints.leads,
      idFields: const ['lead_id'],
      query: q,
      scope: {if (ref.watch(leadArchivedProvider)) 'is_archive': true},
    ),
  );
  return all
      .where((l) => matches([l.id], leadMatchesQuery(l, q)))
      .toList();
});

/// The local half of the lead search — what the card itself can answer while
/// the server round-trip is in flight.
bool leadMatchesQuery(Lead l, String q) =>
    l.name.toLowerCase().contains(q) ||
    (l.company ?? '').toLowerCase().contains(q) ||
    l.project.toLowerCase().contains(q) ||
    l.id.toLowerCase().contains(q);

/// The rows on screen: the base list narrowed by the active tab and the search
/// box.
///
/// The drawer filters are **not** applied here in API mode — the server already
/// ran them, so [leadBaseProvider] *is* the matching set. Tab and search stay
/// local because they run over that complete result, not over a partial page.
final visibleLeadsProvider = Provider<List<Lead>>((ref) {
  final base = ref.watch(leadSearchedProvider);
  final selected = ref.watch(leadTabProvider);
  final lanes = {for (final t in ref.watch(leadTabsProvider)) if (t.id != 'all') t.id};
  Iterable<Lead> out = base;
  if (selected.contains(leadOtherTab)) {
    out = out.where((l) => !lanes.contains(l.stageKey));
  } else {
    // A chip tapped before the status catalog resolved can name a stage the
    // org does not have; ignore it instead of silently emptying the list.
    final chosen = selected.where(lanes.contains).toSet();
    if (chosen.isNotEmpty) out = out.where((l) => chosen.contains(l.stageKey));
  }
  // Mock mode has no query engine behind it, so the drawer is matched here.
  if (!ApiConfig.apiEnabled) {
    final filters = ref.watch(leadFiltersProvider);
    if (!filters.isEmpty) out = out.where((l) => leadMatchesFilters(l, filters));
  }
  // The search box is already applied by [leadSearchedProvider].
  return out.toList();
});

/// Count of leads for a given tab key within [base].
int leadTabCount(List<Lead> base, String key, {Set<String> lanes = const {}}) {
  if (key == 'all') return base.length;
  if (key == leadOtherTab) return base.where((l) => !lanes.contains(l.stageKey)).length;
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


/// Who a **new** lead may be owned by or assigned to — the webapp's
/// `GET /management/assignable-users/?module=lead`. The server only returns
/// staff and roles that can read leads; anyone else would be refused with
/// "Cannot assign to …". Empty on failure, and the form then falls back to the
/// org roster.
final leadAssignableUsersProvider = FutureProvider.autoDispose<List<CatalogOption>>((ref) async {
  if (!ApiConfig.apiEnabled) return const [];
  try {
    final body = await ref.read(apiServiceProvider).get(
      ApiEndpoints.assignableUsers,
      query: {'module': 'lead', 'page_size': 200},
      quiet: true,
    );
    return [
      for (final u in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results)
        if (u['user_id'] != null)
          CatalogOption(
            id: '${u['user_id']}',
            name: '${u['full_name'] ?? u['email'] ?? ''}'.trim(),
          ),
    ];
  } on Object {
    return const [];
  }
});

/// Teams a lead may be assigned to — the webapp's
/// `GET /management/assignable-teams/?module=lead` (readable by CRM roles,
/// unlike `/management/teams/`).
final leadAssignableTeamsProvider = FutureProvider.autoDispose<List<CatalogOption>>((ref) async {
  final body = await ref.read(apiServiceProvider).get(
    ApiEndpoints.assignableTeams,
    query: {'module': 'lead', 'page_size': 100},
  );
  return [
    for (final t in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results)
      if ((t['team_id'] ?? t['id']) != null)
        CatalogOption(id: '${t['team_id'] ?? t['id']}', name: '${t['name'] ?? ''}'),
  ];
});

/// Users a new record of [module] (`task`, `followup`, …) may be assigned to —
/// `GET /management/assignable-users/?module=…`, as the webapp's task forms
/// ask. Empty on failure; callers then fall back to the org roster.
/// `GET /management/assignable-teams/?module=` — the teams a record of that
/// module may be assigned to (tasks read `module=task`).
final assignableTeamsForModuleProvider =
    FutureProvider.autoDispose.family<List<CatalogOption>, String>((ref, module) async {
  if (!ApiConfig.apiEnabled) return const [];
  final body = await ref.read(apiServiceProvider).get(
    ApiEndpoints.assignableTeams,
    query: {'module': module, 'page_size': 100},
    quiet: true,
  );
  return [
    for (final t in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results)
      if ((t['team_id'] ?? t['id']) != null)
        CatalogOption(id: '${t['team_id'] ?? t['id']}', name: '${t['name'] ?? ''}'),
  ];
});

final assignableUsersForModuleProvider =
    FutureProvider.autoDispose.family<List<CatalogOption>, String>((ref, module) async {
  if (!ApiConfig.apiEnabled) return const [];
  try {
    final body = await ref.read(apiServiceProvider).get(
      ApiEndpoints.assignableUsers,
      query: {'module': module, 'page_size': 200},
      quiet: true,
    );
    return [
      for (final u in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results)
        if (u['user_id'] != null)
          CatalogOption(id: '${u['user_id']}', name: '${u['full_name'] ?? u['email'] ?? ''}'.trim()),
    ];
  } on Object {
    return const [];
  }
});
