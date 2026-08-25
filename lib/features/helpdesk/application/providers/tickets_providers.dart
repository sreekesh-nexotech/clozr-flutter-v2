import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../core/network/network_providers.dart';
import '../../../crm/application/providers/customers_providers.dart';
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
    FutureProvider.family<List<Ticket>, TicketListQuery>(
  (ref, q) => ref.watch(ticketsRepositoryProvider).getTickets(filters: q.filters),
);

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
final ticketStatusCatalogProvider = FutureProvider<List<CatalogOption>>(
  (ref) => ref.watch(ticketsRepositoryProvider).getIssueStatuses(),
);

/// The org's own issue types (`/crm/issue-types/`) — the Category chips.
final ticketTypeCatalogProvider = FutureProvider<List<CatalogOption>>(
  (ref) => ref.watch(ticketsRepositoryProvider).getIssueTypes(),
);

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

final ticketFilterParamsProvider = Provider<Map<String, dynamic>>(
  (ref) => ticketFilterParamsFor(
    mine: ref.watch(ticketMineProvider),
    breach: ref.watch(ticketBreachingProvider),
    search: ref.watch(ticketSearchProvider),
    statusTab: ref.watch(ticketTabProvider),
    catalog: ref.watch(ticketStatusOptionsProvider),
    drawer: ref.watch(ticketFiltersProvider),
  ),
);

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
  final raw = await ref
      .watch(ticketsRepositoryProvider)
      .getStatusCounts(ref.watch(ticketFilterParamsProvider));
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
  return ref.watch(ticketsRepositoryProvider).getSummary(const {});
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

/// Applied drawer filters for the Tickets list (the source of the badge count).
///
/// Declared here rather than beside the drawer spec so the query params can
/// read it without the providers importing the spec back.
final ticketFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Active status tab.
final ticketTabProvider = StateProvider<String>((ref) => 'all');

/// Search query.
final ticketSearchProvider = StateProvider<String>((ref) => '');

/// Whether the search field is expanded.
final ticketSearchOpenProvider = StateProvider<bool>((ref) => false);

/// "My Tickets" default view — assignees include me (the prototype's default).
final ticketMineProvider = StateProvider<bool>((ref) => true);

/// "Breaching soon" chip — filter to tickets due within the next hour.
final ticketBreachingProvider = StateProvider<bool>((ref) => false);

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
  final tab = ref.watch(ticketTabProvider);
  final mine = ref.watch(ticketMineProvider);
  final breach = ref.watch(ticketBreachingProvider);
  final q = ref.watch(ticketSearchProvider).trim().toLowerCase();

  Iterable<Ticket> out = base;
  // The tab and the search are server-side in API mode too; only the "All tab
  // hides closed work" rule below is the app's own.
  if (tab != 'all' && !ApiConfig.apiEnabled) {
    out = out.where((t) => t.status == tab);
  } else if (tab == 'all' && mine && !breach) {
    out = out.where((t) => t.status != 'resolved' && t.status != 'closed');
  }
  if (q.isNotEmpty) {
    final dir = ref.watch(ticketDirectoryProvider);
    out = out.where((t) {
      final cust = dir.customer(t.custId);
      return '${t.subject} ${t.id} ${t.cat} ${cust?.display ?? ''}'.toLowerCase().contains(q);
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
final boardExpandedProvider = StateProvider<Map<String, bool>>((ref) => {'breached': true});
