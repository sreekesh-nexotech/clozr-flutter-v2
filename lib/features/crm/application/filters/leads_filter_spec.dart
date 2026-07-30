import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/lead.dart';
import '../providers/leads_providers.dart';

/// Leads filter — the reference wiring of the spec-driven engine (audit §2).
///
/// Option lists that the audit marks admin-configurable (sources, products,
/// teams) are derived here from the seed data so the reference drawer actually
/// filters; swap these for Settings-backed lists when the API lands.

/// Team names present in the roster (excludes the admin's "You").
List<String> _allTeams() {
  final seen = <String>{};
  for (final u in MockUsers.reps) {
    final t = u.team;
    if (t.isNotEmpty && t != 'You') seen.add(t);
  }
  final list = seen.toList()..sort();
  return list;
}

/// Team names a lead touches (owner + assigned members).
Set<String> teamNamesOfLead(Lead l) {
  final ids = <String>{l.owner, ...l.team};
  final teams = <String>{};
  for (final id in ids) {
    final t = MockUsers.of(id).team;
    if (t.isNotEmpty && t != 'You') teams.add(t);
  }
  return teams;
}

const _months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// Parse a lead's `createdOn` display string ("08 Dec 2025") to a DateTime.
DateTime? parseLeadDate(String s) {
  final parts = s.trim().split(RegExp(r'\s+'));
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = _months[parts[1]];
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  return DateTime(year, month, day);
}

/// Build the Leads drawer spec from the current lead set.
FilterSpec buildLeadsFilterSpec(List<Lead> leads) {
  final sources = (leads.map((l) => l.source).toSet().toList()..sort())
      .map((s) => FilterOption(id: s, label: s))
      .toList();
  final products = (leads.map((l) => l.project).toSet().toList()..sort())
      .map((p) => FilterOption(id: p, label: p))
      .toList();
  final stages = [
    for (final k in StatusMeta$.leadAll) FilterOption(id: k, label: StatusMeta$.lead[k]!.label),
  ];
  final teams = _allTeams().map((t) => FilterOption(id: t, label: t)).toList();
  final users = [
    for (final u in MockUsers.reps) FilterOption(id: u.id, label: u.name),
  ];

  return FilterSpec(
    title: 'Filter by:',
    sections: [
      FilterSection(title: 'Lead information', fields: [
        FilterField(
            id: 'sources',
            label: 'Source',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            options: sources),
        FilterField(
            id: 'products',
            label: 'Product / Service',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: products),
        FilterField(
            id: 'stages',
            label: 'Stage',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            options: stages),
        const FilterField(
            id: 'aging',
            label: 'Aging in stage',
            control: FilterControl.radio,
            options: [
              FilterOption(id: 'any', label: 'Any'),
              FilterOption(id: '14', label: 'Stale 14+ days'),
              FilterOption(id: '30', label: 'Stale 30+ days'),
            ]),
      ]),
      FilterSection(title: 'Ownership & assignment', fields: [
        const FilterField(
            id: 'ownerMode',
            label: 'Lead owner',
            control: FilterControl.radio,
            options: [
              FilterOption(id: 'all', label: 'All'),
              FilterOption(id: 'me', label: 'Me'),
              FilterOption(id: 'none', label: 'Unassigned'),
            ]),
        FilterField(
            id: 'owners',
            label: 'Select users',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search user…',
            options: users),
        FilterField(
            id: 'teams',
            label: 'Team',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            options: teams),
      ]),
      FilterSection(title: 'Activity & engagement', fields: [
        const FilterField(
            id: 'created',
            label: 'Created',
            control: FilterControl.dateRange,
            dateChips: ['today', 'yesterday', 'last7', 'last30', 'last60', 'last90', 'month']),
        const FilterField(
            id: 'value',
            label: 'Deal value',
            control: FilterControl.numberRange,
            unit: '₹ lakhs',
            unitScale: 100000),
      ]),
      FilterSection(title: 'Lead score', fields: [
        const FilterField(
            id: 'score',
            label: 'Lead score',
            control: FilterControl.radio,
            options: [
              FilterOption(id: 'all', label: 'All'),
              FilterOption(id: 'hot', label: 'Hot (75+)'),
              FilterOption(id: 'warm', label: 'Warm (45–74)'),
              FilterOption(id: 'cold', label: 'Cold (<45)'),
            ]),
      ]),
    ],
  );
}

/// Evaluate a lead against applied filter values. Multi-valued controls use the
/// pure [FilterMatch] helpers; radios carry module-specific thresholds.
bool leadMatchesFilters(Lead l, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('sources'), [l.source])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('products'), [l.project])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('stages'), [l.status])) return false;

  final aging = v.radio('aging');
  if (aging != null && aging.isActive) {
    final threshold = int.tryParse(aging.id) ?? 0;
    if (l.statusDays < threshold) return false;
  }

  final owner = v.radio('ownerMode');
  if (owner != null && owner.isActive) {
    if (owner.id == 'me' && l.owner != 'me') return false;
    if (owner.id == 'none' && l.owner.isNotEmpty) return false;
  }

  if (!FilterMatch.matchAnyOf(v.choice('owners'), [l.owner])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('teams'), teamNamesOfLead(l))) return false;

  if (!FilterMatch.matchDate(v.date('created'), parseLeadDate(l.createdOn))) return false;
  if (!FilterMatch.matchRange(v.range('value'), l.valueNum, scale: 100000)) return false;

  final score = v.radio('score');
  if (score != null && score.isActive) {
    final n = l.score;
    switch (score.id) {
      case 'hot':
        if (n < 75) return false;
      case 'warm':
        if (!(n >= 45 && n < 75)) return false;
      case 'cold':
        if (n >= 45) return false;
    }
  }
  return true;
}

// ── Providers ──

/// The Leads drawer spec, derived from the loaded lead catalog.
final leadsFilterSpecProvider = Provider<FilterSpec>((ref) {
  final leads = ref.watch(leadsProvider).valueOrNull ?? const [];
  return buildLeadsFilterSpec(leads);
});

/// Applied drawer filters for the Leads list (the source of the badge count).
final leadFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Leads list (bookmark chips).
final leadSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
