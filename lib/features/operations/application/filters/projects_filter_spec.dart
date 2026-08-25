import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/application/providers/customers_providers.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
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
FilterSpec buildProjectsFilterSpec(
  List<Project> projects, {
  List<AppUser>? roster,
  List<CatalogOption> statusCatalog = const [],
  List<CatalogOption> typeCatalog = const [],
  List<CatalogOption> customerCatalog = const [],
}) {
  final r = roster ?? MockUsers.reps;
  // Types and statuses from their own facet endpoints (`operations.md` §3, §4).
  // Derived from the loaded rows they could only offer values some already
  // visible project has, so you could not filter *to* anything absent from the
  // current page — and statuses were the built-in vocabulary regardless of what
  // the org actually named its own.
  final types = typeCatalog.isNotEmpty
      ? [for (final t in typeCatalog) FilterOption(id: t.name, label: t.name)]
      : (projects.map((p) => p.type).where((t) => t.isNotEmpty).toSet().toList()..sort())
          .map((t) => FilterOption(id: t, label: t))
          .toList();
  final statuses = statusCatalog.isNotEmpty
      ? [for (final s in statusCatalog) FilterOption(id: s.name, label: s.name)]
      : [
          for (final k in StatusMeta$.project.keys)
            FilterOption(id: k, label: StatusMeta$.project[k]!.label),
        ];
  // The org's customers from `/crm/customers/`, falling back to the names on
  // loaded rows. Derived alone, the facet could only offer a customer some
  // already-visible project has — so you could not filter *to* one whose
  // projects were off the current page, which is the whole point of filtering.
  final companies = customerCatalog.isNotEmpty
      ? [for (final c in customerCatalog) FilterOption(id: c.name, label: c.name)]
      : (projects
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
bool projectMatchesFilters(Project p, FilterValues v, {bool serverApplied = false}) {
  // Skipped when the server already ran them. Re-applying is not merely
  // redundant: the server matched on ids, while these match on the display
  // values a row carries — so a status the org renamed, or a customer matched by
  // name, would be filtered out a second time and wrongly.
  if (!serverApplied) {
    if (!FilterMatch.matchAnyOf(v.choice('types'), [p.type])) return false;
    if (!FilterMatch.matchAnyOf(
        v.choice('statuses'), [p.status, if (p.statusName.isNotEmpty) p.statusName])) {
      return false;
    }
    if (!FilterMatch.matchAnyOf(v.choice('pri'), [p.pri])) return false;
    if (!FilterMatch.matchAnyOf(v.choice('customer'),
        [p.internal ? '__internal' : (p.company ?? '')])) {
      return false;
    }
    if (!FilterMatch.matchAnyOf(v.choice('managers'), [p.manager])) return false;
  }

  // Always local — `operations.md` §1 documents no param for these; see
  // [ProjectFilterCodec.localOnlyFields].
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
    ref.watch(allProjectsProvider),
    roster: ref.watch(rosterProvider),
    // These three were accepted by the builder and never passed, so the drawer
    // silently took every fallback: Status showed the built-in vocabulary
    // instead of the org's own — while the tab strip directly above it showed
    // the real one — and Type and Customer were scraped off loaded rows.
    statusCatalog: ref.watch(projectStatusOptionsProvider),
    typeCatalog: ref.watch(projectTypeOptionsProvider),
    customerCatalog: [
      for (final c in ref.watch(customersProvider).valueOrNull ?? const [])
        CatalogOption(
          id: c.id,
          name: (c.company?.trim().isNotEmpty ?? false) ? c.company! : c.name,
        ),
    ],
  );
});

/// Applied drawer filters for the Projects list (the source of the badge count).
final projectFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Projects list (bookmark chips).
final projectSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
