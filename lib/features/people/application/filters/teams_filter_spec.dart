import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../domain/entities/member.dart';
import '../../domain/entities/team.dart';
import '../providers/people_providers.dart';

/// Teams filter — spec-driven engine wiring (mirrors the Leads reference).
///
/// Ports the prototype's `MODFDEF.teams` drawer: a Team lead checkbox group
/// (option id = member id, label = member name) and a Team size checkbox group
/// with the small / mid / large buckets.
FilterSpec buildTeamsFilterSpec(List<Team> teams, Map<String, Member> byId) {
  // Distinct leads present across the teams, resolved to member names.
  final leadIds = <String>[];
  for (final t in teams) {
    if (t.lead.isNotEmpty && !leadIds.contains(t.lead)) leadIds.add(t.lead);
  }
  final leadOpts = [
    for (final id in leadIds) FilterOption(id: id, label: byId[id]?.name ?? id),
  ];

  return FilterSpec(
    title: 'Filter teams',
    sections: [
      FilterSection(title: 'Team lead', fields: [
        FilterField(
          id: 'leads',
          label: 'Team lead',
          control: FilterControl.checkboxGroup,
          options: leadOpts,
        ),
      ]),
      const FilterSection(title: 'Team size', fields: [
        FilterField(
          id: 'sizes',
          label: 'Team size',
          control: FilterControl.checkboxGroup,
          options: [
            FilterOption(id: 'small', label: '1–2 members'),
            FilterOption(id: 'mid', label: '3–5 members'),
            FilterOption(id: 'large', label: '6+ members'),
          ],
        ),
      ]),
    ],
  );
}

/// Evaluate a team against applied filter values (mirrors the prototype's
/// `teamsFilt.leads` / `teamsFilt.sizes` list filters).
bool teamMatchesFilters(Team t, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('leads'), [t.lead])) return false;

  final sizes = v.choice('sizes');
  if (sizes != null && sizes.isActive) {
    final n = t.members.length;
    final hit = sizes.ids.any((sz) => switch (sz) {
          'small' => n <= 2,
          'mid' => n >= 3 && n <= 5,
          'large' => n >= 6,
          _ => false,
        });
    if (sizes.isNot ? hit : !hit) return false;
  }
  return true;
}

// ── Providers ──

/// The Teams drawer spec, derived from the loaded teams + member lookup.
final teamsFilterSpecProvider = Provider<FilterSpec>((ref) {
  final teams = ref.watch(teamsProvider).valueOrNull ?? const [];
  final byId = ref.watch(membersByIdProvider);
  return buildTeamsFilterSpec(teams, byId);
});

/// Applied drawer filters for the Teams list (the source of the badge count).
final teamFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Teams list (bookmark chips).
final teamSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());

/// The Teams list with the search ([visibleTeamsProvider]) AND the applied
/// drawer filters applied. The screen renders this.
final filteredTeamsProvider = Provider<List<Team>>((ref) {
  final base = ref.watch(visibleTeamsProvider);
  final filters = ref.watch(teamFiltersProvider);
  if (filters.isEmpty) return base;
  return base.where((t) => teamMatchesFilters(t, filters)).toList();
});
