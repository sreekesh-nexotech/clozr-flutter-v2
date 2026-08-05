import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/project.dart';
import '../../presentation/components/ops_widgets.dart';
import '../providers/projects_providers.dart';

/// Projects filter — spec-driven engine wiring for the Operations Projects list
/// (ported 1:1 from the prototype's `_fspec.projects`). Follows the Leads
/// reference: build a [FilterSpec] from the loaded data, expose it plus an
/// applied-values provider and a saved-views controller, and match rows with the
/// pure [FilterMatch] helpers.

/// Team names present in the roster (excludes the admin's "You").
List<String> _allTeams(List<AppUser> roster) {
  final seen = <String>{};
  for (final u in roster) {
    final t = u.team;
    if (t.isNotEmpty && t != 'You') seen.add(t);
  }
  final list = seen.toList()..sort();
  return list;
}

/// Team names a project touches (manager + assignees).
Set<String> teamNamesOfProject(Project p) {
  final ids = <String>{p.manager, ...p.assignees};
  final teams = <String>{};
  for (final id in ids) {
    final t = MockUsers.of(id).team;
    if (t.isNotEmpty && t != 'You') teams.add(t);
  }
  return teams;
}

/// The prototype's cost parser: "₹18L" → 1800000, "₹1.2Cr" → 12000000.
double projectCostRupees(Project p) {
  final v = p.cost;
  final n = double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
  if (RegExp(r'cr', caseSensitive: false).hasMatch(v)) return n * 10000000;
  if (RegExp(r'l', caseSensitive: false).hasMatch(v)) return n * 100000;
  return n;
}

/// The project's expected-end date (ISO preferred, display fallback).
DateTime? projectEndDate(Project p) =>
    DateTime.tryParse(p.endISO) ?? opsParseDisplayDate(p.end);

/// Build the Projects drawer spec from the current project set. [roster] supplies
/// the manager/assignee/team options (real members in API mode, prototype reps
/// in mock mode); null defaults to the mock reps.
FilterSpec buildProjectsFilterSpec(List<Project> projects, {List<AppUser>? roster}) {
  final r = roster ?? MockUsers.reps;
  final types = (projects.map((p) => p.type).where((t) => t.isNotEmpty).toSet().toList()..sort())
      .map((t) => FilterOption(id: t, label: t))
      .toList();
  final statuses = [
    for (final k in StatusMeta$.project.keys) FilterOption(id: k, label: StatusMeta$.project[k]!.label),
  ];
  final companies = (projects
          .where((p) => !p.internal && (p.company ?? '').isNotEmpty)
          .map((p) => p.company!)
          .toSet()
          .toList()
        ..sort())
      .map((c) => FilterOption(id: c, label: c))
      .toList();
  final customerOpts = <FilterOption>[
    const FilterOption(id: '__internal', label: 'Internal project'),
    ...companies,
  ];
  final teams = _allTeams(r).map((t) => FilterOption(id: t, label: t)).toList();
  final users = [
    for (final u in r) FilterOption(id: u.id, label: u.name),
  ];

  return FilterSpec(
    title: 'Filter projects by:',
    sections: [
      FilterSection(title: 'Project information', fields: [
        FilterField(
            id: 'types',
            label: 'Project type',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: types),
        FilterField(
            id: 'statuses',
            label: 'Status',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: statuses),
        const FilterField(
            id: 'pri',
            label: 'Priority',
            control: FilterControl.checkboxGroup,
            options: [
              FilterOption(id: 'High', label: 'High'),
              FilterOption(id: 'Medium', label: 'Medium'),
              FilterOption(id: 'Low', label: 'Low'),
            ]),
        FilterField(
            id: 'customer',
            label: 'Customer',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search customer…',
            options: customerOpts),
      ]),
      FilterSection(title: 'Ownership & assignment', fields: [
        FilterField(
            id: 'managers',
            label: 'Project manager',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search user…',
            options: users),
        FilterField(
            id: 'assignees',
            label: 'Assignees',
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
      FilterSection(title: 'Health & schedule', fields: [
        const FilterField(
            id: 'health',
            label: 'Schedule health',
            control: FilterControl.radio,
            options: [
              FilterOption(id: 'any', label: 'Any'),
              FilterOption(id: 'overdue', label: 'Overdue'),
              FilterOption(id: 'risk', label: 'Due in 14 days'),
              FilterOption(id: 'ontrack', label: 'On track'),
            ]),
        const FilterField(
            id: 'end',
            label: 'Expected end',
            control: FilterControl.dateRange,
            dateChips: ['overdue', 'today', 'next7', 'next30', 'next60', 'next90']),
        const FilterField(
            id: 'start',
            label: 'Expected start',
            control: FilterControl.dateRange,
            dateChips: ['today', 'yesterday', 'last7', 'last30', 'last60', 'last90', 'month']),
        const FilterField(
            id: 'cost',
            label: 'Estimated cost',
            control: FilterControl.numberRange,
            unit: '₹ lakhs',
            unitScale: 100000),
      ]),
    ],
  );
}

/// Evaluate a project against applied filter values.
bool projectMatchesFilters(Project p, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('types'), [p.type])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('statuses'), [p.status])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('pri'), [p.pri])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('customer'), [p.internal ? '__internal' : (p.company ?? '')])) {
    return false;
  }

  if (!FilterMatch.matchAnyOf(v.choice('managers'), [p.manager])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('assignees'), p.assignees)) return false;
  if (!FilterMatch.matchAnyOf(v.choice('teams'), teamNamesOfProject(p))) return false;

  final health = v.radio('health');
  if (health != null && health.isActive) {
    final open = p.status != 'completed' && p.status != 'cancelled';
    final end = projectEndDate(p);
    if (end == null) {
      if (health.id != 'ontrack') return false;
    } else {
      final days = end.difference(kFilterToday).inDays;
      switch (health.id) {
        case 'overdue':
          if (!(open && days < 0)) return false;
        case 'risk':
          if (!(open && days >= 0 && days <= 14)) return false;
        case 'ontrack':
          if (!(!open || days > 14)) return false;
      }
    }
  }

  if (!FilterMatch.matchDate(v.date('end'), projectEndDate(p))) return false;
  if (!FilterMatch.matchDate(v.date('start'), opsParseDisplayDate(p.start))) return false;
  if (!FilterMatch.matchRange(v.range('cost'), projectCostRupees(p), scale: 100000)) return false;

  return true;
}

// ── Providers ──

/// The Projects drawer spec, derived from the loaded project catalog.
final projectsFilterSpecProvider = Provider<FilterSpec>((ref) {
  return buildProjectsFilterSpec(
    ref.watch(projectsListProvider),
    roster: ref.watch(rosterProvider),
  );
});

/// Applied drawer filters for the Projects list (the source of the badge count).
final projectFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Projects list (bookmark chips).
final projectSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
