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

/// The drawer's facets → documented `IssueFilter` params.
///
/// Only the facets whose option ids are the values the API stores are
/// translated; the rest stay with the client-side matcher, which keeps running
/// over whatever the server returns:
///
/// * **Category, Company, Product** — the drawer's options are display *names*
///   (a ticket carries `type_name` / `customer_name`, not the ids), and the API
///   filters on `issue_type` / `customer` / `product` **uuids**. Sending a name
///   would match nothing at all, which is worse than filtering locally.
/// * **"Due < 1h" / "Due today" / "On track" / "Paused"** — computed from the
///   SLA clock against now; only `breached` has a stored flag.
/// * **is-not selections** — the API's `__not` variants exist, but the client
///   matcher already expresses them and mixing the two risks a double negative.
Map<String, dynamic> ticketDrawerParams(
  FilterValues values,
  List<CatalogOption> catalog,
) {
  final out = <String, dynamic>{};

  // Status: the drawer holds the org's own `issue_status_id`s, which is what
  // `status__in` takes. A folded key can still arrive from a saved view stored
  // before the catalog was wired, so those are resolved through the catalog.
  final statuses = values.choice('statuses');
  if (statuses != null && statuses.isActive && !statuses.isNot) {
    final known = {for (final s in catalog) s.id};
    final ids = <String>{
      for (final id in statuses.ids)
        if (known.contains(id)) id else ...ticketStatusIdsFor(id, catalog),
    };
    if (ids.isNotEmpty) out['status__in'] = ids.join(',');
  }

  // Priority: the drawer offers the API's own words, so they pass straight
  // through. "Urgent" is the display fold and is translated for the same
  // saved-view reason as above.
  final pri = values.choice('pri');
  if (pri != null && pri.isActive && !pri.isNot) {
    final names = [for (final p in pri.ids) p == 'Urgent' ? 'Critical' : p];
    out['priority__in'] = names.join(',');
  }

  // Assignees: the drawer deals in mapped ids ('me'); the API needs the uuid.
  final assignees = values.choice('assignees');
  if (assignees != null && assignees.isActive && !assignees.isNot) {
    final ids = <String>[
      for (final id in assignees.ids)
        if (UserDirectory.realUserId(id) case final real?) real,
    ];
    if (ids.isNotEmpty) out['assigned_to__in'] = ids.join(',');
  }

  // SLA: only the stored flag maps; the clock-based options do not.
  if (values.radio('sla')?.id == 'breached') out['sla_breached'] = 'true';

  // Linked work: the API has a flag for tasks, none for projects.
  if (values.radio('linked')?.id == 'task') out['has_linked_tasks'] = 'true';

  return out;
}

/// The server params the list header's own controls produce.
///
/// These were all applied **client-side** over an eagerly-walked list: the
/// search box, the My/Breaching chips and the status tab could only ever find
/// a ticket that had already been downloaded.
Map<String, dynamic> ticketFilterParamsFor({
  required bool mine,
  required bool breach,
  required String search,
  required String statusTab,
  required List<CatalogOption> catalog,
  FilterValues? drawer,
}) {
  if (!ApiConfig.apiEnabled) return const {};
  // The tab is the org's `issue_status_id` once the catalog has loaded, and a
  // folded built-in key before it does (or in mock mode) — accept both, so the
  // strip keeps working through the switch-over and a chip set from another
  // screen ("show me resolved") still resolves.
  final known = {for (final s in catalog) s.id};
  final statusIds = statusTab == 'all'
      ? const <String>[]
      : (known.contains(statusTab)
          ? [statusTab]
          : ticketStatusIdsFor(statusTab, catalog));
  return {
    if (mine) 'assigned_to_me': 'true',
    if (breach) 'sla_breached': 'true',
    if (search.trim().isNotEmpty) 'search': search.trim(),
    // Omitted when the catalog has not loaded: sending nothing shows every
    // ticket, which is recoverable; sending an empty `status__in` shows none.
    if (statusIds.isNotEmpty) 'status__in': statusIds.join(','),
    // The drawer last, so its own Status selection refines the tab rather than
    // being overwritten by it.
    if (drawer != null) ...ticketDrawerParams(drawer, catalog),
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
