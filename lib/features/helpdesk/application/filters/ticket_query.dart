import '../../../../core/config/api_config.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../data/api/status_keys.dart';
import '../../../crm/domain/entities/crm_catalog.dart';

/// Builds the `/crm/issues/` query the tickets list sends
/// (`issue-filters.md` Part 4).
///
/// Kept apart from the providers so the contract is testable on its own — the
/// providers pull in the filter spec, and through it the icon package, which
/// does not compile under the pinned Flutter.

/// The `issue_status_id`s whose org name folds into a UI tab key
/// (`new|open|pending|resolved|closed`).
///
/// One tab can cover several org statuses — an org with both "Open" and "In
/// Progress" reads both as Open — so `status__in` takes a csv.
List<String> ticketStatusIdsFor(String uiKey, List<CatalogOption> catalog) => [
      for (final s in catalog)
        if (ticketStatusKey(s.name) == uiKey) s.id,
    ];

/// The drawer's SLA facet id for a Support Overview section.
///
/// The board's bucket keys and the facet's option ids were named separately —
/// only `lt1h` / `risk` differ — so "+N more" has to translate rather than pass
/// its key straight through. Null for anything that is not a board section.
///
/// Applying the facet is what makes that link land on the section the user was
/// looking at: `breached` also narrows server-side via `sla_breached`
/// (`helpdesk.md` §SLA), and the other three are clock-based, so only the
/// client matcher can resolve them.
String? ticketSlaFacetForBoard(String sectionKey) => switch (sectionKey) {
      'breached' => 'breached',
      'lt1h' => 'risk',
      'today' => 'today',
      'ontrack' => 'ontrack',
      _ => null,
    };

/// The drawer's seven webapp facets → the `/crm/issues/` params
/// (`issue-filters.md` Part 4): `<field>__in` for "is", `<field>__not` for
/// "is not". The webapp list sends `__not_in` for exclusion, which this
/// backend ignores (DEF-HD-012); `__not` takes the same csv and is honoured
/// for every facet (verified live), so the rows *and* the counts narrow.
///
/// The mobile-only facets stay with the client matcher: the clock-based SLA
/// buckets ("Due < 1h", "Due today", "On track", "Paused") and "has a linked
/// project" / "no linked work" have no param; only `sla_breached` and
/// `has_linked_tasks` do.
Map<String, dynamic> ticketDrawerParams(
  FilterValues values,
  List<CatalogOption> catalog,
) {
  final out = <String, dynamic>{};

  void put(String field, ChoiceValue? choice, Iterable<String> ids) {
    if (choice == null || !choice.isActive) return;
    final list = ids.where((v) => v.isNotEmpty).toSet().toList();
    if (list.isEmpty) return;
    out['$field${choice.isNot ? '__not' : '__in'}'] = list.join(',');
  }

  // Status: the org's own `issue_status_id`s. A folded key can still arrive
  // from another screen ("show me resolved"), so those resolve via the catalog.
  final statuses = values.choice('statuses');
  if (statuses != null) {
    final known = {for (final s in catalog) s.id};
    put('status', statuses, [
      for (final id in statuses.ids)
        if (known.contains(id)) id else ...ticketStatusIdsFor(id, catalog),
    ]);
  }
  // Priority: the API's own words ("Urgent" is the old display fold).
  final pri = values.choice('pri');
  put('priority', pri, [for (final p in pri?.ids ?? const <String>{}) p == 'Urgent' ? 'Critical' : p]);
  // Assignees: the drawer deals in mapped ids ('me'); the API needs the uuid.
  final assignees = values.choice('assignees');
  put('assigned_to', assignees, [
    for (final id in assignees?.ids ?? const <String>{})
      if (UserDirectory.realUserId(id) case final real?) real,
  ]);
  // Category / Product / Project / Customer: option ids are the uuids.
  put('issue_type', values.choice('cats'), values.choice('cats')?.ids ?? const {});
  put('product', values.choice('products'), values.choice('products')?.ids ?? const {});
  put('project', values.choice('projects'), values.choice('projects')?.ids ?? const {});
  put('customer', values.choice('companies'), values.choice('companies')?.ids ?? const {});

  // SLA: only the stored flag maps; the clock-based options do not.
  if (values.radio('sla')?.id == 'breached') out['sla_breached'] = 'true';

  // Linked work: the API has a flag for tasks, none for projects.
  if (values.radio('linked')?.id == 'task') out['has_linked_tasks'] = 'true';

  return out;
}

/// The `issue_status_id`s a set of status chips stands for. Chips hold the
/// org's ids once the catalog has loaded; a folded built-in key (set from
/// another screen, or before the catalog lands) resolves through it.
List<String> ticketChipStatusIds(Set<String> chips, List<CatalogOption> catalog) {
  final known = {for (final s in catalog) s.id};
  return <String>{
    for (final c in chips)
      if (known.contains(c)) c else ...ticketStatusIdsFor(c, catalog),
  }.toList();
}

/// The server params for the Tickets list — the webapp's `effectiveFilters`
/// (or, with [forCounts], its `baseFilters`: the status chips and the
/// "My Tickets hides resolved work" rule are left out, so every chip shows
/// what picking it would produce).
///
/// * "My Tickets" → `assigned_to_me=true`; with no chip picked it also hides
///   every resolved status (`status__not=<resolved ids>`), as the webapp does.
/// * Status chips are multi-select and OR together (`status__in=<ids>`).
/// * An applied saved view is resolved by the server from `saved_filter_id`;
///   only the search travels with it (webapp `issueQuery`).
Map<String, dynamic> ticketFilterParamsFor({
  required bool mine,
  required bool breach,
  required String search,
  required Set<String> statusChips,
  required List<CatalogOption> catalog,
  FilterValues? drawer,
  String? savedFilterId,
  bool forCounts = false,
}) {
  if (!ApiConfig.apiEnabled) return const {};
  final q = search.trim();
  if (savedFilterId != null && savedFilterId.isNotEmpty) {
    return {'saved_filter_id': savedFilterId, if (q.isNotEmpty) 'search': q};
  }
  final chipIds = ticketChipStatusIds(statusChips, catalog);
  final resolvedIds = [for (final s in catalog) if (s.isClosed) s.id];
  return {
    if (mine) 'assigned_to_me': 'true',
    if (breach) 'sla_breached': 'true',
    if (q.isNotEmpty) 'search': q,
    // The drawer before the chips, so a picked chip narrows on top of it.
    if (drawer != null) ...ticketDrawerParams(drawer, catalog),
    if (!forCounts && chipIds.isNotEmpty) 'status__in': chipIds.join(','),
    if (!forCounts && chipIds.isEmpty && mine && resolvedIds.isNotEmpty)
      'status__not': resolvedIds.join(','),
  };
}

/// Folds `/crm/issues/status-counts/` (keyed by `issue_status_id`) onto the UI
/// tab keys, summing the org statuses that share a tab.
Map<String, int> foldTicketCounts(
  Map<String, int> raw,
  List<CatalogOption> catalog,
) {
  if (raw.isEmpty) return const {};
  // Both keyings live in one map — the tab strip reads org ids once the
  // catalog has loaded and folded keys before it does. Uuids and keys like
  // 'open' cannot collide.
  final out = <String, int>{...raw, 'all': raw['all'] ?? 0};
  for (final s in catalog) {
    final n = raw[s.id];
    if (n == null) continue;
    final key = ticketStatusKey(s.name);
    out[key] = (out[key] ?? 0) + n;
  }
  return out;
}
