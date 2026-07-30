import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/mock/mock_users.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/lead.dart';
import '../providers/customers_providers.dart';
import '../providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import 'tasks_filter_spec.dart' show parseCrmDate;

/// Follow-ups filter — spec-driven drawer (audit §4). Wired exactly like the
/// Leads reference. Sections: Type & status · People & company · Due date.

const List<String> _fuTypes = ['Call', 'Email', 'Meeting', 'WhatsApp', 'Site visit', 'Payment'];

const Map<String, IconData> _fuTypeIcons = {
  'Call': PhosphorIconsRegular.phone,
  'Email': PhosphorIconsRegular.envelopeSimple,
  'Meeting': PhosphorIconsRegular.usersThree,
  'WhatsApp': PhosphorIconsRegular.whatsappLogo,
  'Site visit': PhosphorIconsRegular.mapPin,
  'Payment': PhosphorIconsRegular.currencyInr,
};

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
}) {
  final users = [
    for (final u in MockUsers.reps) FilterOption(id: u.id, label: u.name),
  ];
  final companies = _allCompanies(leads, customers, followups)
      .map((c) => FilterOption(id: c, label: c))
      .toList();
  final types = [
    for (final t in _fuTypes) FilterOption(id: t, label: t, icon: _fuTypeIcons[t]),
  ];

  return FilterSpec(
    title: 'Follow-ups',
    sections: [
      FilterSection(title: 'Type & status', fields: [
        FilterField(
            id: 'types',
            label: 'Type',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: types),
        const FilterField(
            id: 'statuses',
            label: 'Status',
            control: FilterControl.checkboxGroup,
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
  return buildFollowupsFilterSpec(leads: leads, customers: customers, followups: followups);
});

/// Applied drawer filters for the Follow-ups list (the source of the badge).
final followupFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Follow-ups list (bookmark chips).
final followupSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
