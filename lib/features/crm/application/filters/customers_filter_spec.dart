import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/lead.dart';
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
}) {
  final statuses = [
    for (final k in StatusMeta$.customerOrder)
      FilterOption(id: k, label: StatusMeta$.customer[k]!.label),
  ];
  final sources = (customers.map((c) => c.source).toSet().toList()..sort())
      .map((s) => FilterOption(id: s, label: s))
      .toList();
  final users = [
    for (final u in MockUsers.reps) FilterOption(id: u.id, label: u.name),
  ];
  final companies = _allCompanies(leads, customers)
      .map((c) => FilterOption(id: c, label: c))
      .toList();
  final products = (customers.map((c) => c.project).toSet().toList()..sort())
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
  return buildCustomersFilterSpec(customers: customers, leads: leads);
});

/// Applied drawer filters for the Customers list (the source of the badge).
final customerFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Customers list (bookmark chips).
final customerSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
