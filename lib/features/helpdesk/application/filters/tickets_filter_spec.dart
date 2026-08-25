import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../domain/entities/ticket.dart';
import '../../infrastructure/data_sources/local/tickets_mock_ds.dart';
import '../../presentation/util/ticket_sla.dart';
import '../providers/tickets_providers.dart';

/// Tickets filter — the helpdesk wiring of the spec-driven filter engine,
/// ported 1:1 from the prototype's unified filter (`_fspec.tickets` / `fMatch`).
///
/// Option lists that the prototype derives from the live ticket set (category,
/// channel, product, customer) are derived here the same way so the drawer
/// actually filters; assignee options come from the shared roster
/// (`MockUsers.reps`, the prototype's `REPS`).

/// The canonical due-date quick chips the prototype's Resolve-by field exposes.
const _dueChips = ['overdue', 'today', 'tomorrow', 'next7', 'next30', 'next60', 'next90'];

/// The display label for a ticket's linked customer (company, falling back to
/// the contact name) — the value the Customer filter matches against. Pass the
/// resolved [lookups] (from `ticketDirectoryProvider`) so API mode reads real
/// customers; null defaults to the mock [TicketDirectory] (mock mode).
String ticketCustomerDisplay(Ticket t, [TicketLookups? lookups]) {
  final c = lookups != null
      ? lookups.customer(t.custId)
      : TicketDirectory.customer(t.custId);
  return c?.display ?? '';
}

/// SLA bucket for a ticket, ported from the prototype's `tktSlaState`. Only
/// new/open tickets have a live SLA state; everything else returns null. Uses
/// the board anchor (09:41), matching the prototype.
String? ticketSlaState(Ticket t) {
  if (t.status != 'new' && t.status != 'open') return null;
  final iso = (t.responded == null && t.respByISO != null) ? t.respByISO : t.resolveByISO;
  if (iso == null) return 'ontrack';
  final d = DateTime.parse(iso).millisecondsSinceEpoch;
  final now = kNowBoard.millisecondsSinceEpoch;
  if (d < now) return 'breached';
  if (d - now < 3600000) return 'risk';
  if (d <= kEod.millisecondsSinceEpoch) return 'today';
  return 'ontrack';
}

List<FilterOption> _uniqueOptions(Iterable<String?> values) {
  final set = <String>{for (final v in values) if (v != null && v.isNotEmpty) v};
  final list = set.toList()..sort();
  return [for (final v in list) FilterOption(id: v, label: v)];
}

/// Build the Tickets drawer spec from the current ticket set. [lookups] resolves
/// customer options from real data in API mode; [roster] supplies the assignee
/// options (real members in API mode, prototype reps in mock mode).
/// The priorities the API stores (`issue-filters.md` Part 4). The app displays
/// "Critical" as "Urgent", but the filter offers — and sends — the server's own
/// word.
const kIssuePriorities = ['Critical', 'High', 'Medium', 'Low'];

FilterSpec buildTicketsFilterSpec(List<Ticket> tickets,
    {TicketLookups? lookups,
    List<AppUser>? roster,
    List<CatalogOption> statusCatalog = const []}) {
  // The org's own statuses, keyed by `issue_status_id` — which is what
  // `status__in` takes. Previously this was the built-in five with their
  // labels painted on, so a status outside them ("In Progress", "Overdue",
  // "Duplicate") was not selectable at all.
  final statuses = statusCatalog.isNotEmpty
      ? [for (final s in statusCatalog) FilterOption(id: s.id, label: s.name)]
      // No catalog (mock mode, a failed fetch): the built-in vocabulary, which
      // is also what the rows carry there.
      : [
          for (final e in StatusMeta$.ticket.entries)
            FilterOption(id: e.key, label: e.value.label),
        ];
  final priorities = [
    for (final p in kIssuePriorities) FilterOption(id: p, label: p),
  ];
  final cats = _uniqueOptions(tickets.map((t) => t.cat));
  final products = _uniqueOptions(tickets.map((t) => t.product));
  final customers = _uniqueOptions(tickets.map((t) => ticketCustomerDisplay(t, lookups)));
  final assignees = [
    for (final u in (roster ?? MockUsers.reps)) FilterOption(id: u.id, label: u.name),
  ];

  return FilterSpec(
    title: 'Filter tickets by:',
    sections: [
      FilterSection(title: 'Ticket information', fields: [
        FilterField(
            id: 'statuses',
            label: 'Status',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: statuses),
        FilterField(
            id: 'pri',
            label: 'Priority',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: priorities),
        FilterField(
            id: 'cats',
            label: 'Category',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: cats),
      ]),
      FilterSection(title: 'Customer & assignment', fields: [
        FilterField(
            id: 'companies',
            label: 'Customer',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search customer…',
            options: customers),
        FilterField(
            id: 'assignees',
            label: 'Assignee',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search user…',
            options: assignees),
        FilterField(
            id: 'products',
            label: 'Product / Service',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search product…',
            options: products),
      ]),
      FilterSection(title: 'SLA & dates', fields: [
        const FilterField(
            id: 'sla',
            label: 'SLA status',
            control: FilterControl.radio,
            options: [
              FilterOption(id: 'any', label: 'Any'),
              FilterOption(id: 'breached', label: 'Breached'),
              FilterOption(id: 'risk', label: 'Due < 1h'),
              FilterOption(id: 'today', label: 'Due today'),
              FilterOption(id: 'ontrack', label: 'On track'),
              FilterOption(id: 'paused', label: 'Paused (pending)'),
            ]),
        const FilterField(
            id: 'linked',
            label: 'Linked work',
            control: FilterControl.radio,
            options: [
              FilterOption(id: 'any', label: 'Any'),
              FilterOption(id: 'proj', label: 'Has linked project'),
              FilterOption(id: 'task', label: 'Has linked task'),
              FilterOption(id: 'none', label: 'No linked work'),
            ]),
        const FilterField(
            id: 'resolveBy',
            label: 'Resolve by',
            control: FilterControl.dateRange,
            dateChips: _dueChips),
      ]),
    ],
  );
}

/// Evaluate a ticket against applied filter values. Multi-valued controls use
/// the pure [FilterMatch] helpers; radios carry helpdesk-specific logic. Pass
/// [lookups] so the Customer filter matches real display names in API mode.
bool ticketMatchesFilters(Ticket t, FilterValues v, [TicketLookups? lookups]) {
  // Both vocabularies are offered to the matcher: the org's id/name (what the
  // drawer now holds, and what the server filtered on) and the folded key /
  // display word, which is all a mock row has.
  if (!FilterMatch.matchAnyOf(v.choice('statuses'),
      [t.status, if (t.statusId.isNotEmpty) t.statusId, if (t.statusName.isNotEmpty) t.statusName])) {
    return false;
  }
  if (!FilterMatch.matchAnyOf(
      v.choice('pri'), [t.pri, if (t.priorityName.isNotEmpty) t.priorityName])) {
    return false;
  }
  if (!FilterMatch.matchAnyOf(v.choice('cats'), [t.cat])) return false;

  if (!FilterMatch.matchAnyOf(v.choice('companies'), [ticketCustomerDisplay(t, lookups)])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('assignees'), t.assignees)) return false;
  if (!FilterMatch.matchAnyOf(v.choice('products'), [if (t.product != null) t.product!])) return false;

  final sla = v.radio('sla');
  if (sla != null && sla.isActive) {
    if (sla.id == 'paused') {
      if (t.status != 'pending') return false;
    } else if (ticketSlaState(t) != sla.id) {
      return false;
    }
  }

  final linked = v.radio('linked');
  if (linked != null && linked.isActive) {
    switch (linked.id) {
      case 'proj':
        if (t.projId == null) return false;
      case 'task':
        if (t.taskId == null) return false;
      case 'none':
        if (t.projId != null || t.taskId != null) return false;
    }
  }

  if (!FilterMatch.matchDate(
      v.date('resolveBy'),
      t.resolveByISO == null ? null : DateTime.parse(t.resolveByISO!))) {
    return false;
  }
  return true;
}

// ── Providers ──

/// The Tickets drawer spec, derived from the loaded ticket set.
final ticketsFilterSpecProvider = Provider<FilterSpec>((ref) {
  final tickets = ref.watch(ticketsProvider).valueOrNull ?? const [];
  return buildTicketsFilterSpec(
    tickets,
    lookups: ref.watch(ticketDirectoryProvider),
    roster: ref.watch(rosterProvider),
    statusCatalog: ref.watch(ticketStatusOptionsProvider),
  );
});

/// Saved views for the Tickets list (bookmark chips).
final ticketSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());

/// The visible ticket list (tab + quick chips + search, from
/// [visibleTicketsProvider]) with the drawer filters applied on top.
final filteredTicketsProvider = Provider<List<Ticket>>((ref) {
  final base = ref.watch(visibleTicketsProvider);
  final filters = ref.watch(ticketFiltersProvider);
  if (filters.isEmpty) return base;
  final dir = ref.watch(ticketDirectoryProvider);
  return base.where((t) => ticketMatchesFilters(t, filters, dir)).toList();
});
