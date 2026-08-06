import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/mock/mock_users.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/lead.dart';
import '../providers/crm_catalog_providers.dart';
import '../providers/customers_providers.dart';
import '../providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import 'tasks_filter_spec.dart' show parseCrmDate;

/// Follow-ups filter — spec-driven drawer (audit §4). Wired exactly like the
/// Leads reference. Sections: Type & status · People & company · Due date.

/// The built-in type vocabulary, used only when the org's catalog has not
/// loaded (mock mode, or a failed fetch).
///
/// It is a **fallback, not the source of truth**: follow-up types are org-
/// editable and rows join on the type *name* exactly, so a hard-coded list
/// silently matches nothing the moment an org renames or adds one.
const List<String> kBuiltinFollowupTypes = [
  'Call', 'Email', 'Meeting', 'WhatsApp', 'Site visit', 'Payment',
];

/// All companies across leads + customers + follow-ups (the audit's company
/// universe), sorted and de-duplicated.
List<String> _allCompanies(List<Lead> leads, List<Customer> customers, List<Followup> fus) {
  final seen = <String>{};
  for (final l in leads) {
    final c = l.company;
    if (c != null && c.isNotEmpty) seen.add(c);
  }
  for (final c in customers) {
    final name = c.company ?? c.name;
    if (name.isNotEmpty) seen.add(name);
  }
  for (final f in fus) {
    if (f.company.isNotEmpty) seen.add(f.company);
  }
  final list = seen.toList()..sort();
  return list;
}

/// Build the Follow-ups drawer spec (audit §4).
FilterSpec buildFollowupsFilterSpec({
  required List<Lead> leads,
  required List<Customer> customers,
  required List<Followup> followups,
  List<AppUser> roster = MockUsers.reps,
  List<CatalogOption> typeCatalog = const [],
}) {
  final users = [
    for (final u in roster) FilterOption(id: u.id, label: u.name),
  ];
  final companies = _allCompanies(leads, customers, followups)
      .map((c) => FilterOption(id: c, label: c))
      .toList();
  // The org's own types when the catalog has loaded, otherwise the built-in
  // vocabulary. Both the option id and its label are the type **name**, which
  // is what a follow-up row carries and what the matcher compares.
  final typeNames = typeCatalog.isNotEmpty
      ? [for (final t in typeCatalog) t.name]
      : kBuiltinFollowupTypes;
  final types = [
    for (final t in typeNames) FilterOption(id: t, label: t),
  ];

  return FilterSpec(
    title: 'Follow-ups',
    sections: [
      // Type and status carry the is / is not toggle, like the Leads drawer's
      // Source / Product / Stage. The matcher already honoured `isNot` on every
      // field here — these two simply never offered the control, so "everything
      // except Email" could not be expressed.
      FilterSection(title: 'Type & status', fields: [
        FilterField(
            id: 'types',
            label: 'Type',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: types),
        const FilterField(
            id: 'statuses',
            label: 'Status',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: [
              FilterOption(id: 'due', label: 'Upcoming'),
              FilterOption(id: 'overdue', label: 'Overdue'),
              FilterOption(id: 'done', label: 'Done'),
            ]),
      ]),
      FilterSection(title: 'People & company', fields: [
        FilterField(
            id: 'owners',
            label: 'Assigned to',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search user…',
            options: users),
        FilterField(
            id: 'companies',
            label: 'Company',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search company…',
            options: companies),
      ]),
      FilterSection(title: 'Due date', fields: [
        const FilterField(
            id: 'due',
            label: 'Due date',
            control: FilterControl.dateRange,
            dateChips: ['overdue', 'today', 'tomorrow', 'next7', 'next30', 'next60', 'next90']),
      ]),
    ],
  );
}

/// Evaluate a follow-up against applied filter values.
bool followupMatchesFilters(Followup f, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('types'), [f.kind])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('statuses'), [f.status])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('owners'), [f.owner])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('companies'), [f.company])) return false;
  if (!FilterMatch.matchDate(v.date('due'), parseCrmDate(f.due))) return false;
  return true;
}

// ── Providers ──

/// The Follow-ups drawer spec, derived from the company universe.
final followupsFilterSpecProvider = Provider<FilterSpec>((ref) {
  final leads = ref.watch(leadsProvider).valueOrNull ?? const [];
  final customers = ref.watch(customersProvider).valueOrNull ?? const [];
  final followups = ref.watch(followupsAllProvider);
  return buildFollowupsFilterSpec(
    leads: leads,
    customers: customers,
    followups: followups,
    roster: ref.watch(rosterProvider),
    typeCatalog: ref.watch(followupTypeOptionsProvider),
  );
});

/// Applied drawer filters for the Follow-ups list (the source of the badge).
final followupFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Follow-ups list (bookmark chips).
final followupSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
