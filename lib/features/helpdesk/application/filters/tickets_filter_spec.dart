import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../data/api/user_directory.dart';
import '../../../crm/application/providers/crm_catalog_providers.dart';
import '../../../crm/application/providers/customers_providers.dart';
import '../../../crm/domain/entities/customer.dart';
import '../../../operations/application/providers/projects_providers.dart';
import '../../../../core/filters/filter_models.dart';
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

/// The priorities the API stores (`issue-filters.md` Part 4).
const kIssuePriorities = ['Critical', 'High', 'Medium', 'Low'];

/// The Tickets drawer — the webapp's seven facets in its order (Status,
/// Priority, Assignee, Category, Product / Service, Project, Customer), each
/// with is / is not, every option list taken from the org rather than from the
/// rows on screen. The mobile-only SLA / linked-work / resolve-by section
/// follows them.
///
/// Mock mode (no catalogs) falls back to the values the loaded rows carry.
FilterSpec buildTicketsFilterSpec(List<Ticket> tickets,
    {TicketLookups? lookups,
    List<AppUser>? roster,
    List<CatalogOption> statusCatalog = const [],
    List<CatalogOption> typeCatalog = const [],
    List<CatalogOption> productCatalog = const [],
    List<FilterOption> projects = const [],
    List<FilterOption> customers = const []}) {
  final statuses = statusCatalog.isNotEmpty
      ? [for (final s in statusCatalog) FilterOption(id: s.id, label: s.name)]
      : [
          for (final e in StatusMeta$.ticket.entries)
            FilterOption(id: e.key, label: e.value.label),
        ];
  final priorities = [for (final p in kIssuePriorities) FilterOption(id: p, label: p)];
  final cats = typeCatalog.isNotEmpty
      ? [for (final t in typeCatalog) FilterOption(id: t.id, label: t.name)]
      : _uniqueOptions(tickets.map((t) => t.cat));
  final products = productCatalog.isNotEmpty
      ? [for (final p in productCatalog) FilterOption(id: p.id, label: p.name)]
      : _uniqueOptions(tickets.map((t) => t.product));
  final custs = customers.isNotEmpty
      ? customers
      : _uniqueOptions(tickets.map((t) => ticketCustomerDisplay(t, lookups)));
  final projs = projects.isNotEmpty ? projects : _uniqueOptions(tickets.map((t) => t.projName));
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
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: priorities),
        FilterField(
            id: 'assignees',
            label: 'Assignee',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search teammates…',
            options: assignees),
        FilterField(
            id: 'cats',
            label: 'Category',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: cats),
      ]),
      FilterSection(title: 'Product, project & customer', fields: [
        FilterField(
            id: 'products',
            label: 'Product / Service',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search products…',
            options: products),
        FilterField(
            id: 'projects',
            label: 'Project',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search projects…',
            options: projs),
        FilterField(
            id: 'companies',
            label: 'Customer',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search customers…',
            options: custs),
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

/// Evaluate a ticket against applied filter values.
///
/// With [serverApplied] (API mode) the seven webapp facets were already sent as
/// `__in` / `__not` params, so only the facets with no param are checked here —
/// re-matching ids against display values would only drop rows the server
/// rightly returned. Mock mode matches everything locally.
bool ticketMatchesFilters(Ticket t, FilterValues v,
    [TicketLookups? lookups, bool serverApplied = false]) {
  if (!serverApplied) {
    if (!FilterMatch.matchAnyOf(v.choice('statuses'),
        [t.status, if (t.statusId.isNotEmpty) t.statusId, if (t.statusName.isNotEmpty) t.statusName])) {
      return false;
    }
    if (!FilterMatch.matchAnyOf(
        v.choice('pri'), [t.pri, if (t.priorityName.isNotEmpty) t.priorityName])) {
      return false;
    }
    if (!FilterMatch.matchAnyOf(v.choice('cats'), [t.cat, if (t.typeId.isNotEmpty) t.typeId])) return false;
    if (!FilterMatch.matchAnyOf(
        v.choice('companies'), [ticketCustomerDisplay(t, lookups), t.custId])) {
      return false;
    }
    if (!FilterMatch.matchAnyOf(v.choice('assignees'), t.assignees)) return false;
    if (!FilterMatch.matchAnyOf(v.choice('products'),
        [if (t.product != null) t.product!, if (t.productId != null) t.productId!])) {
      return false;
    }
    if (!FilterMatch.matchAnyOf(v.choice('projects'),
        [if (t.projName != null) t.projName!, if (t.projId != null) t.projId!])) {
      return false;
    }
  }

  final sla = v.radio('sla');
  if (sla != null && sla.isActive && !(serverApplied && sla.id == 'breached')) {
    if (sla.id == 'paused') {
      if (t.status != 'pending') return false;
    } else if (ticketSlaState(t) != sla.id) {
      return false;
    }
  }

  final linked = v.radio('linked');
  if (linked != null && linked.isActive && !(serverApplied && linked.id == 'task')) {
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

/// The drawer's facets ↔ a saved filter's `filter_definition` — the webapp's
/// `buildIssueSavedFilterDefinition` / `parseIssueSavedFilterDefinition`.
///
/// `<field>__in` for "is", `<field>__not` for "is not". The saved-filter
/// validator accepts `__not` only for status, priority, assignee and category,
/// so an "is not" on Product / Project / Customer is left out and named in
/// [TicketViewDefinition.unsupported] for the warning toast.
class TicketViewDefinition {
  const TicketViewDefinition(this.definition, this.unsupported);
  final Map<String, dynamic> definition;
  final List<String> unsupported;
}

const _viewFacets = <(String, String, bool, String)>[
  ('statuses', 'status', true, 'Status'),
  ('pri', 'priority', true, 'Priority'),
  ('assignees', 'assigned_to', true, 'Assignee'),
  ('cats', 'issue_type', true, 'Category'),
  ('products', 'product', false, 'Product'),
  ('projects', 'project', false, 'Project'),
  ('companies', 'customer', false, 'Customer'),
];

TicketViewDefinition encodeTicketView(FilterValues v) {
  final out = <String, dynamic>{};
  final unsupported = <String>[];
  for (final (field, key, canExclude, label) in _viewFacets) {
    final c = v.choice(field);
    if (c == null || !c.isActive) continue;
    final ids = [
      for (final id in c.ids)
        if (field == 'assignees') UserDirectory.realUserId(id) ?? '' else if (field == 'pri' && id == 'Urgent') 'Critical' else id,
    ].where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) continue;
    if (c.isNot && !canExclude) {
      unsupported.add(label);
      continue;
    }
    out['$key${c.isNot ? '__not' : '__in'}'] = ids.join(',');
  }
  return TicketViewDefinition(out, unsupported);
}

FilterValues decodeTicketView(Map<String, dynamic> definition) {
  List<String> split(Object? raw) => '${raw ?? ''}'
      .replaceAll(RegExp(r'[\[\]"]'), '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final out = FilterValues();
  for (final (field, key, _, _) in _viewFacets) {
    final isIn = definition.containsKey('${key}__in');
    final isNot = definition.containsKey('${key}__not');
    if (!isIn && !isNot) continue;
    final ids = split(definition[isIn ? '${key}__in' : '${key}__not']);
    out[field] = ChoiceValue(
      ids: {for (final id in ids) field == 'assignees' ? UserDirectory.mapUserId(id) : id},
      isNot: !isIn,
    );
  }
  return out;
}

// ── Providers ──

/// The org catalogs behind the drawer's options; the sheet takes its spec
/// once, so the Tickets screen awaits these before opening it.
final ticketFilterCatalogsProvider = FutureProvider<void>((ref) async {
  await Future.wait<Object?>([
    ref.watch(ticketStatusCatalogProvider.future),
    ref.watch(ticketTypeCatalogProvider.future),
    ref.watch(productCatalogProvider.future).catchError((_) => const <CatalogOption>[]),
    ref.watch(customersProvider.future).catchError((_) => const <Customer>[]),
  ]);
});

/// The Tickets drawer spec, from the org's own catalogs.
final ticketsFilterSpecProvider = Provider<FilterSpec>((ref) {
  final tickets = ref.watch(ticketsProvider).valueOrNull ?? const [];
  return buildTicketsFilterSpec(
    tickets,
    lookups: ref.watch(ticketDirectoryProvider),
    roster: ref.watch(rosterProvider),
    statusCatalog: ref.watch(ticketStatusOptionsProvider),
    typeCatalog: ref.watch(ticketTypeOptionsProvider),
    productCatalog: ref.watch(productOptionsProvider),
    projects: [
      for (final p in ref.watch(allProjectsProvider)) FilterOption(id: p.id, label: p.name),
    ],
    customers: [
      for (final c in ref.watch(customersProvider).valueOrNull ?? const <Customer>[])
        FilterOption(id: c.id, label: (c.company ?? '').isNotEmpty ? c.company! : c.name),
    ],
  );
});

/// The visible ticket list (chips + quick chips + search, from
/// [visibleTicketsProvider]) with the drawer's mobile-only facets applied on
/// top (the webapp facets are already server-side in API mode).
final filteredTicketsProvider = Provider<List<Ticket>>((ref) {
  final base = ref.watch(visibleTicketsProvider);
  final filters = ref.watch(ticketFiltersProvider);
  if (filters.isEmpty) return base;
  final dir = ref.watch(ticketDirectoryProvider);
  return base.where((t) => ticketMatchesFilters(t, filters, dir, ApiConfig.apiEnabled)).toList();
});
