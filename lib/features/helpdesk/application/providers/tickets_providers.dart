import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/api_endpoints.dart';
import '../board_rules.dart';
import '../../../../core/auth/session_gate.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../../auth/application/providers/module_perm_providers.dart';
import '../../../crm/application/providers/customers_providers.dart';
import '../../../crm/application/providers/saved_filters_providers.dart';
import '../../../crm/domain/entities/customer.dart';
import '../../../operations/application/providers/projects_providers.dart';
import '../../../operations/domain/entities/project.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../filters/ticket_query.dart';
import '../../../crm/domain/entities/audit_entry.dart';
import '../../domain/entities/issue_summary.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/entities/ticket_task.dart';
import '../../domain/repositories/tickets_repository.dart';
import '../../infrastructure/data_sources/local/tickets_mock_ds.dart';
import '../../infrastructure/data_sources/remote/tickets_remote_ds.dart';
import '../../infrastructure/repositories/tickets_api_repository.dart';
import '../../infrastructure/repositories/tickets_repository_impl.dart';
import '../../presentation/util/ticket_sla.dart';

/// DI seam: API-backed when `--dart-define=API_BASE_URL` is set, mock-backed
/// otherwise (the app behaves exactly as the presentation build did).
final ticketsRepositoryProvider = Provider<TicketsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const TicketsRepositoryImpl(TicketsMockDataSource());
  }
  return TicketsApiRepository(
    TicketsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Async source of all tickets.
/// Org-wide tickets — the cross-screen lookup source (the detail screen, the
/// Helpdesk home and the boards all read it), so it carries no list filters.
final ticketsProvider = FutureProvider<List<Ticket>>(
  (ref) => ref.watch(ticketsScopedProvider(const TicketListQuery()).future),
);

/// The query key for one ticket fetch.
class TicketListQuery {
  const TicketListQuery({this.filters = const {}});

  final Map<String, dynamic> filters;

  String get signature {
    final keys = filters.keys.toList()..sort();
    return [for (final k in keys) '$k=${filters[k]}'].join('&');
  }

  @override
  bool operator ==(Object other) =>
      other is TicketListQuery && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

/// Tickets for one query — the server does the filtering.
final ticketsScopedProvider =
    FutureProvider.family<List<Ticket>, TicketListQuery>((ref, q) async {
  // No list for a role without Helpdesk (an assignee opening their own
  // ticket): the server refuses it, and that 403 is not the user's doing.
  if (!ref.watch(helpdeskReadableProvider)) return const [];
  return ref.watch(ticketsRepositoryProvider).getTickets(filters: q.filters);
});

/// Drops every fetched ticket list so the next read goes to the server.
///
/// Invalidating [ticketsProvider] (or [ticketsFilteredProvider]) does **not**:
/// they only re-run their bodies, which re-read the still-cached
/// [ticketsScopedProvider] future and hand back the very same rows. That is why
/// a saved edit used to come back to the detail screen unchanged, and why every
/// pull-to-refresh in helpdesk quietly did nothing. Every refresh gesture and
/// every write must go through here.
void refreshTickets(WidgetRef ref) => ref.invalidate(ticketsScopedProvider);

/// The org's own issue statuses (`/crm/issue-statuses/`).
///
/// Empty — no request — for a role without the Helpdesk module: a ticket's
/// assignee may still open their ticket (and its audit log, which reads this),
/// but the catalog answers them 403, and that refusal must not toast.
final ticketStatusCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  if (!ref.watch(helpdeskReadableProvider)) return const [];
  return ref.watch(ticketsRepositoryProvider).getIssueStatuses();
});

/// The org's own issue types (`/crm/issue-types/`) — the Category chips.
final ticketTypeCatalogProvider = FutureProvider<List<CatalogOption>>((ref) async {
  if (!ref.watch(helpdeskReadableProvider)) return const [];
  return ref.watch(ticketsRepositoryProvider).getIssueTypes();
});

/// Whether the signed-in role holds the Helpdesk (`issue`) module — the
/// webapp's `hasModule('issue')`. True while access is unknown (mock mode, a
/// failed `/auth/me/modules/`), when nothing is gated.
final helpdeskReadableProvider =
    Provider<bool>((ref) => ref.watch(modulePermProvider('issue')).read);

/// Whether the role may change tickets (`issue` update) — the webapp's
/// `can('update')` behind every write control on the ticket.
final helpdeskEditableProvider =
    Provider<bool>((ref) => ref.watch(modulePermProvider('issue')).update);

/// Synchronous view of the type catalog; empty means "use the built-in
/// Complaint / Request / Query vocabulary".
final ticketTypeOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(ticketTypeCatalogProvider).valueOrNull ?? const [],
);

/// Synchronous view — empty while in flight, in mock mode and on failure, which
/// callers read as "use the built-in vocabulary".
final ticketStatusOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(ticketStatusCatalogProvider).valueOrNull ?? const [],
);

/// The list's server params — the webapp's `effectiveFilters` (see
/// [ticketFilterParamsFor]).
final ticketFilterParamsProvider = Provider<Map<String, dynamic>>(
  (ref) => ticketFilterParamsFor(
    mine: ref.watch(ticketMineProvider),
    breach: ref.watch(ticketBreachingProvider),
    search: ref.watch(ticketSearchProvider),
    statusChips: ref.watch(ticketStatusChipsProvider),
    catalog: ref.watch(ticketStatusOptionsProvider),
    drawer: ref.watch(ticketFiltersProvider),
    savedFilterId: ref.watch(ticketSavedFiltersProvider.select((s) => s.activeId)),
  ),
);

/// The chip counts' params — the webapp's `baseFilters`: everything but the
/// status chips themselves (and the resolved-work rule that rides on them).
final ticketCountParamsProvider = Provider<Map<String, dynamic>>(
  (ref) => ticketFilterParamsFor(
    mine: ref.watch(ticketMineProvider),
    breach: ref.watch(ticketBreachingProvider),
    search: ref.watch(ticketSearchProvider),
    statusChips: ref.watch(ticketStatusChipsProvider),
    catalog: ref.watch(ticketStatusOptionsProvider),
    drawer: ref.watch(ticketFiltersProvider),
    savedFilterId: ref.watch(ticketSavedFiltersProvider.select((s) => s.activeId)),
    forCounts: true,
  ),
);

/// Saved views for the Tickets list — `/crm/saved-filters/` with module
/// `issue`, the same views the webapp lists (save, apply, update, delete).
/// Reloaded per signed-in user; kept in memory only for a role that cannot
/// read Helpdesk.
final ticketSavedFiltersProvider =
    StateNotifierProvider<SavedFiltersController, SavedFiltersState>((ref) {
  ref.watch(helpdeskSessionUserProvider);
  return SavedFiltersController(
    module: 'issue',
    remote: ref.watch(helpdeskReadableProvider) ? ref.watch(savedFiltersRemoteProvider) : null,
  );
});

/// The tickets list itself, with the header's own controls resolved by the
/// server where the API supports it.
final ticketsFilteredProvider = FutureProvider<List<Ticket>>(
  (ref) => ref.watch(
    ticketsScopedProvider(
      TicketListQuery(filters: ref.watch(ticketFilterParamsProvider)),
    ).future,
  ),
);

/// The tab strip's counts, from `/crm/issues/status-counts/` under the same
/// filters as the list, folded from `issue_status_id` onto the UI tab keys.
///
/// Empty (mock mode, a failed call) means the strip falls back to counting the
/// rows it has — which is only right when every page happens to be downloaded.
final ticketStatusCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  // Same gate as the list: a role without Helpdesk would only be refused.
  if (!ref.watch(helpdeskReadableProvider)) return const {};
  final raw = await ref
      .watch(ticketsRepositoryProvider)
      .getStatusCounts(ref.watch(ticketCountParamsProvider));
  return foldTicketCounts(raw, ref.watch(ticketStatusOptionsProvider));
});

/// One ticket's activity feed, from the ticket's **own** endpoint
/// (`helpdesk.md` §10).
///
/// Not the org-wide audit trail: that needs `view_audit_log`, and on this org
/// it answers 0 rows for a ticket whose own feed has 8. The uuids the server
/// leaves in a summary ("Status changed to f164d805-…") are resolved here from
/// the status catalog and the roster.
final ticketActivityProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>, String>((ref, issueId) {
  ref.watch(apiWriteTickProvider);
  final names = <String, String>{
    for (final s in ref.watch(ticketStatusOptionsProvider)) s.id: s.name,
  };
  for (final u in ref.watch(rosterProvider)) {
    final real = UserDirectory.realUserId(u.id);
    if (real != null) names[real] = u.name;
  }
  return ref.watch(ticketsRepositoryProvider).getActivity(issueId, names: names);
});

/// One ticket, read directly (`GET /crm/issues/{id}/`).
///
/// The detail screen prefers this over the list row: it is one call rather than
/// a walk of the whole org list, so a saved edit shows up as soon as the write
/// returns, and a ticket outside the loaded pages still opens. Watches the write
/// tick, so an edit made anywhere lands here. Null in mock mode and on failure.
final ticketDetailProvider =
    FutureProvider.autoDispose.family<Ticket?, String>((ref, id) {
  ref.watch(apiWriteTickProvider);
  return ref.watch(ticketsRepositoryProvider).getTicket(id);
});

/// The Operations tasks raised from one ticket (`helpdesk.md` §10) — the
/// Linked tasks card.
///
/// Watches the write tick so raising a task from the ticket refreshes the card
/// without a manual pull.
final ticketLinkedTasksProvider =
    FutureProvider.autoDispose.family<List<TicketTask>, String>((ref, issueId) {
  ref.watch(apiWriteTickProvider);
  return ref.watch(ticketsRepositoryProvider).getLinkedTasks(issueId);
});

/// One parent's direct children (`issues/{id}/children/`) — the Child
/// tickets tab. Empty on failure, which reads as "No child tickets".
final ticketChildrenProvider =
    FutureProvider.autoDispose.family<List<Ticket>, String>((ref, issueId) async {
  ref.watch(apiWriteTickProvider);
  try {
    return await ref.watch(ticketsRepositoryProvider).getChildren(issueId);
  } on Object {
    return const [];
  }
});

/// "Attach a child ticket" candidates for the typed search: tickets without
/// a parent (webapp `isChild: false`), first 20.
final ticketAttachCandidatesProvider =
    FutureProvider.autoDispose.family<List<Ticket>, String>((ref, search) async {
  try {
    return await ref.watch(ticketsRepositoryProvider).searchRootTickets(search);
  } on Object {
    return const [];
  }
});

/// The Support Overview figures for **my** tickets (`helpdesk.md` §7).
///
/// Scoped by the server with `assigned_to_me=true` rather than by filtering
/// `isMine` over a page of rows, and its SLA buckets are pause-aware — a ticket
/// on hold does not drift toward "breached", which is not reproducible from a
/// list row. Null in mock mode and on failure, which the dashboard reads as
/// "derive it locally".
final myTicketSummaryProvider = FutureProvider<IssueSummary?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  return ref
      .watch(ticketsRepositoryProvider)
      .getSummary(const {'assigned_to_me': 'true'});
});

/// The **org-wide** Support Overview (`helpdesk.md` §7) behind the Boards
/// screen: the stats strip, the four SLA-watch buckets with their capped card
/// lists, Workload and Pipeline.
///
/// Unfiltered, unlike [myTicketSummaryProvider] — the board is an org-wide SLA
/// view, not "my tickets". Null in mock mode and on failure, which the screen
/// reads as "fall back to bucketing the loaded list".
final boardSummaryProvider = FutureProvider<IssueSummary?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  // The Support Overview is the whole page (webapp), so a failure surfaces as
  // the page's error notice instead of a silent fallback. Quiet: the page
  // explains the refusal itself.
  final body = await ref.watch(apiServiceProvider).get(ApiEndpoints.issueSummary,
      query: const {'due_soon_minutes': boardDueSoonMinutes}, quiet: true);
  return IssueSummary.fromJson(body) ?? const IssueSummary();
});

/// Synchronous view of the folded counts; empty means "count locally".
final ticketTabCountsProvider = Provider<Map<String, int>>(
  (ref) => ref.watch(ticketStatusCountsProvider).valueOrNull ?? const {},
);

/// Look up a single ticket by id (used by the detail screen).
final ticketByIdProvider = Provider.family<Ticket?, String>((ref, id) {
  final tickets = ref.watch(ticketsProvider).valueOrNull;
  if (tickets == null) return null;
  for (final t in tickets) {
    if (t.id == id) return t;
  }
  return null;
});

/// Resolves a ticket's linked customer / project to display info. In mock mode
/// these are the ported [TicketDirectory] maps; in API mode they are rebuilt
/// from the real customer + project lists, so a live backend never renders the
/// prototype's fake company names or costs — an unresolved id yields null and
/// the UI falls back to '—' (audit L-6).
class TicketLookups {
  const TicketLookups({required this.customers, required this.projects});

  /// Builds lookups from the real CRM customers + Operations projects. Only
  /// real records are indexed, so an id with no match resolves to null.
  factory TicketLookups.fromData(
      List<Customer> customers, List<Project> projects) {
    return TicketLookups(
      customers: {
        for (final c in customers) c.id: TicketCustomer(c.id, c.name, c.company ?? ''),
      },
      projects: {
        for (final p in projects) p.id: TicketProject(p.id, p.name, p.cost),
      },
    );
  }

  final Map<String, TicketCustomer> customers;
  final Map<String, TicketProject> projects;

  TicketCustomer? customer(String? id) => id == null ? null : customers[id];
  TicketProject? project(String? id) => id == null ? null : projects[id];
}

/// Directory of ticket-linked customer/project display data. Mock maps in mock
/// mode; real data-derived lookups in API mode (audit L-6). Widgets read this
/// instead of the static [TicketDirectory] so fake names/costs never render
/// against a live backend.
final ticketDirectoryProvider = Provider<TicketLookups>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const TicketLookups(
      customers: TicketDirectory.customers,
      projects: TicketDirectory.projects,
    );
  }
  return TicketLookups.fromData(
    ref.watch(customersProvider).valueOrNull ?? const [],
    ref.watch(allProjectsProvider),
  );
});

// ── Tickets list UI state ──

/// Who is signed in — every list-state provider below watches it, so a new
/// sign-in starts on the webapp's defaults (empty search, no status chip, no
/// quick chips, no facets) instead of inheriting the previous user's.
final helpdeskSessionUserProvider = Provider<String>((ref) => ref.watch(
    sessionControllerProvider.select((s) => s.status == SessionStatus.authenticated ? s.user?.id ?? '' : '')));

/// Applied drawer filters for the Tickets list (the source of the badge count).
///
/// Declared here rather than beside the drawer spec so the query params can
/// read it without the providers importing the spec back.
final ticketFiltersProvider = StateProvider<FilterValues>((ref) {
  ref.watch(helpdeskSessionUserProvider);
  return FilterValues();
});

/// The status chips picked — multi-select, OR-ed (webapp `statusIds`). Empty
/// is the "All" chip. Holds org `issue_status_id`s; another screen may put a
/// folded built-in key here ("resolved"), which resolves through the catalog.
final ticketStatusChipsProvider = StateProvider<Set<String>>((ref) {
  ref.watch(helpdeskSessionUserProvider);
  return const <String>{};
});

/// Search query.
final ticketSearchProvider = StateProvider<String>((ref) {
  ref.watch(helpdeskSessionUserProvider);
  return '';
});

/// Whether the search field is expanded.
final ticketSearchOpenProvider = StateProvider<bool>((ref) {
  ref.watch(helpdeskSessionUserProvider);
  return false;
});

/// "My Tickets" quick view — assignees include me.
///
/// Off by default. It used to default **on**, carried over from the prototype
/// where the seed user was an assignee on everything. Against a live backend a
/// signed-in user is often assigned to none, so the Tickets screen opened
/// showing "All (0)" over a workspace holding 27 tickets — and a ticket the
/// user had just raised disappeared the moment it saved, because a new ticket
/// is unassigned. Opening on the full list and letting the user narrow is the
/// safer default: an empty list then means the workspace is empty.
///
/// On by default again, as on the webapp (`preset = 'mine'`): the list opens
/// on the signed-in user's open work. A user with nothing assigned gets the
/// "No tickets assigned to you" state, which offers New Ticket and points at
/// the "All" preset.
final ticketMineProvider = StateProvider<bool>((ref) {
  ref.watch(helpdeskSessionUserProvider);
  return true;
});

/// "Breaching soon" chip — filter to tickets due within the next hour.
final ticketBreachingProvider = StateProvider<bool>((ref) {
  ref.watch(helpdeskSessionUserProvider);
  return false;
});

/// The base list before the status tab (respects My Tickets / Breaching soon).
final ticketBaseProvider = Provider<List<Ticket>>((ref) {
  // In API mode the server already applied `assigned_to_me` / `sla_breached`
  // (see [ticketFilterParamsProvider]); re-filtering here would narrow the
  // result a second time, and `isMine` only knows the rows it has.
  if (ApiConfig.apiEnabled) {
    return ref.watch(ticketsFilteredProvider).valueOrNull ?? const [];
  }
  final all = ref.watch(ticketsProvider).valueOrNull ?? const [];
  final mine = ref.watch(ticketMineProvider);
  final breach = ref.watch(ticketBreachingProvider);
  if (breach) return all.where(ticketBreaching).toList();
  if (mine) return all.where((t) => t.isMine).toList();
  return all.toList();
});

/// Tickets filtered by the active tab + search query.
final visibleTicketsProvider = Provider<List<Ticket>>((ref) {
  final base = ref.watch(ticketBaseProvider);
  // In API mode the server already applied the chips, the My Tickets scope
  // (resolved work hidden) and the search — re-filtering here dropped rows
  // the server matched, e.g. a search for "TKT-0006" (DEF-HD-009).
  if (ApiConfig.apiEnabled) return base;
  final chips = ref.watch(ticketStatusChipsProvider);
  final mine = ref.watch(ticketMineProvider);
  final breach = ref.watch(ticketBreachingProvider);
  final q = ref.watch(ticketSearchProvider).trim().toLowerCase();

  Iterable<Ticket> out = base;
  if (chips.isNotEmpty) {
    out = out.where((t) => chips.contains(t.status) || chips.contains(t.statusId));
  } else if (mine && !breach) {
    out = out.where((t) => t.status != 'resolved' && t.status != 'closed');
  }
  if (q.isNotEmpty) {
    final dir = ref.watch(ticketDirectoryProvider);
    out = out.where((t) {
      final cust = dir.customer(t.custId);
      return '${t.subject} ${t.displayRef} ${t.cat} ${cust?.display ?? ''}'.toLowerCase().contains(q);
    });
  }
  return out.toList();
});

/// Per-tab count, mirroring the prototype's `tktCount`.
/// The tab's count: the server's when `/crm/issues/status-counts/` answered,
/// else counted over the loaded rows.
int ticketTabCountOf(
  Map<String, int> serverCounts,
  List<Ticket> all,
  bool mine,
  bool breach,
  String key,
) =>
    serverCounts[key] ?? ticketTabCount(all, mine, breach, key);

int ticketTabCount(List<Ticket> all, bool mine, bool breach, String key) {
  final base = mine && !breach
      ? all.where((t) => t.isMine).toList()
      : (breach ? all.where(ticketBreaching).toList() : all);
  if (key == 'all') {
    return mine && !breach ? base.where((t) => t.status != 'resolved' && t.status != 'closed').length : base.length;
  }
  // The key is an org `issue_status_id` once the catalog has loaded, a folded
  // built-in key before it does.
  return base.where((t) => t.status == key || t.statusId == key).length;
}

// ── Helpdesk Home state ──

/// "My Tickets Crossed SLA" value/days segment — true = ₹ Value, false = Days.
final helpSlaValProvider = StateProvider<bool>((ref) => true);

// ── Support Overview (boards) state ──

/// Which SLA-watch sections are expanded (Breached open by default).
final boardExpandedProvider = StateProvider<Map<String, bool>>((ref) {
  ref.watch(helpdeskSessionUserProvider);
  return {'breached': true};
});
