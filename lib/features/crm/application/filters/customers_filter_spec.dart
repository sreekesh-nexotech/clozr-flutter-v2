import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/lead.dart';
import '../../../../data/api/user_directory.dart';
import '../providers/crm_catalog_providers.dart';
import '../providers/customer_activity_providers.dart';
import '../providers/saved_filters_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import 'customer_filter_codec.dart';
import '../providers/customers_providers.dart';
import '../providers/leads_providers.dart';
import 'tasks_filter_spec.dart' show parseCrmDate;

/// Customers filter — spec-driven drawer (audit §6). Wired exactly like the
/// Leads reference. Sections: Status & source · Ownership · Value & tenure.

/// Company universe across leads + customers (the audit's company list).
List<String> _allCompanies(List<Lead> leads, List<Customer> customers) {
  final seen = <String>{};
  for (final l in leads) {
    final c = l.company;
    if (c != null && c.isNotEmpty) seen.add(c);
  }
  for (final c in customers) {
    final name = c.company ?? c.name;
    if (name.isNotEmpty) seen.add(name);
  }
  final list = seen.toList()..sort();
  return list;
}

/// Build the Customers drawer spec (audit §6). Sources and products are derived
/// from the current customer set (admin-configurable / "distinct" in the audit).
FilterSpec buildCustomersFilterSpec({
  required List<Customer> customers,
  required List<Lead> leads,
  List<AppUser> roster = MockUsers.reps,
  List<CatalogOption> statusCatalog = const [],
  List<CatalogOption> sourceCatalog = const [],
  List<CatalogOption> productCatalog = const [],
}) {
  // The org's own statuses when the catalog has loaded, the built-in vocabulary
  // otherwise. The built-ins are only ever right by accident: an org renames its
  // statuses freely, and the drawer used to offer Active / Upsell / Completed /
  // Lost no matter what the org actually calls them.
  final statuses = statusCatalog.isNotEmpty
      ? [for (final s in statusCatalog) FilterOption(id: s.id, label: s.name)]
      : [
          for (final k in StatusMeta$.customerOrder)
            FilterOption(id: k, label: StatusMeta$.customer[k]!.label),
        ];
  // Sources and products come from their own endpoints. Derived from the loaded
  // rows they could only ever offer values some already-visible customer has —
  // so you could not filter *to* anything absent from the current page.
  final sources = sourceCatalog.isNotEmpty
      ? [for (final o in sourceCatalog) FilterOption(id: o.id, label: o.name)]
      : (customers.map((c) => c.source).toSet().toList()..sort())
          .map((s) => FilterOption(id: s, label: s))
          .toList();
  final users = [
    for (final u in roster) FilterOption(id: u.id, label: u.name),
  ];
  final companies = _allCompanies(leads, customers)
      .map((c) => FilterOption(id: c, label: c))
      .toList();
  final products = productCatalog.isNotEmpty
      ? [for (final o in productCatalog) FilterOption(id: o.id, label: o.name)]
      : (customers.map((c) => c.project).toSet().toList()..sort())
          .map((p) => FilterOption(id: p, label: p))
          .toList();

  return FilterSpec(
    title: 'Customers',
    sections: [
      FilterSection(title: 'Status & source', fields: [
        FilterField(
            id: 'statuses',
            label: 'Customer status',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: statuses),
        FilterField(
            id: 'sources',
            label: 'Source',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: sources),
      ]),
      FilterSection(title: 'Ownership', fields: [
        FilterField(
            id: 'owners',
            label: 'Account manager',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search owner…',
            options: users),
        FilterField(
            id: 'companies',
            label: 'Company',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search company…',
            options: companies),
        FilterField(
            id: 'products',
            label: 'Product / Service',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search product…',
            options: products),
      ]),
      FilterSection(title: 'Value & tenure', fields: [
        const FilterField(
            id: 'value',
            label: 'Lifetime value',
            control: FilterControl.numberRange,
            unit: '₹ lakhs',
            unitScale: 100000),
        const FilterField(
            id: 'since',
            label: 'Customer since',
            control: FilterControl.dateRange,
            dateChips: ['today', 'last7', 'last30', 'last60', 'last90', 'month']),
      ]),
    ],
  );
}

/// Evaluate a customer against applied filter values.
bool customerMatchesFilters(Customer c, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('statuses'), [c.status])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('sources'), [c.source])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('owners'), [c.owner])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('companies'), [c.company ?? c.name])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('products'), [c.project])) return false;
  if (!FilterMatch.matchRange(v.range('value'), c.valueNum, scale: 100000)) return false;
  if (!FilterMatch.matchDate(v.date('since'), parseCrmDate(c.createdOn))) return false;
  return true;
}

// ── Providers ──

/// The Customers drawer spec, derived from the loaded customer + lead sets.
final customersFilterSpecProvider = Provider<FilterSpec>((ref) {
  final customers = ref.watch(customersAllProvider);
  final leads = ref.watch(leadsProvider).valueOrNull ?? const [];
  return buildCustomersFilterSpec(
    customers: customers,
    leads: leads,
    roster: ref.watch(rosterProvider),
    statusCatalog: ref.watch(customerStatusOptionsProvider),
    sourceCatalog: ref.watch(leadSourcesProvider),
    productCatalog: ref.watch(productOptionsProvider),
  );
});

/// The org's customer statuses as drawer options.
///
/// Its own provider rather than reusing `customerStatusesProvider` directly:
/// that one yields the repository's `CustomerStatus`, and every filter surface
/// deals in [CatalogOption].
final customerStatusOptionsProvider = Provider<List<CatalogOption>>((ref) => [
      for (final s in ref.watch(customerStatusesProvider))
        CatalogOption(id: s.id, name: s.name),
    ]);

/// Started at mount by the list screen so the drawer never snapshots a
/// half-loaded catalog — the same contract the Leads drawer has.
final customerFilterCatalogsProvider = FutureProvider<void>((ref) async {
  await Future.wait([
    ref.watch(customerStatusCatalogProvider.future),
    ref.watch(leadSourceCatalogProvider.future),
    ref.watch(productCatalogProvider.future),
  ]);
});

/// Translates between the Customers drawer and the stored `filter_definition`.
///
/// Rebuilt as each catalog resolves, so a saved chip applied before they land
/// still decodes correctly once they have.
final customerFilterCodecProvider = Provider<CustomerFilterCodec>(
  (ref) => CustomerFilterCodec(
    statuses: ref.watch(customerStatusOptionsProvider),
    sources: ref.watch(leadSourcesProvider),
    products: ref.watch(productOptionsProvider),
    currentUserId: UserDirectory.currentUserId,
  ),
);

/// Applied drawer filters for the Customers list (the source of the badge).
final customerFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Customers list, backed by `/crm/saved-filters/`.
///
/// Was an in-memory [SavedViewsController]: ids minted from the clock, gone on
/// restart, never sent anywhere. The endpoint is the same one Leads uses and the
/// docs confirm customer saved filters "work exactly like lead saved filters" —
/// it simply was not called with `module: 'customer'`.
final customerSavedViewsProvider =
    StateNotifierProvider<SavedFiltersController, SavedFiltersState>(
  (ref) => SavedFiltersController(
    module: 'customer',
    remote: ref.watch(savedFiltersRemoteProvider),
  ),
);
