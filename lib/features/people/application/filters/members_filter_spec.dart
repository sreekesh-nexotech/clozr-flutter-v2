import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../domain/entities/member.dart';
import '../../domain/entities/team.dart';
import '../providers/people_providers.dart';

/// Members filter — spec-driven engine wiring (mirrors the Leads reference).
///
/// Ports the prototype's `MODFDEF.members` drawer: a Status checkbox group and a
/// Team checkbox group. Role stays as the tab row above the list (not in the
/// drawer), matching the prototype where `memberRole` is a separate tab.
FilterSpec buildMembersFilterSpec(List<Team> teams) {
  final teamOpts = [
    for (final t in teams) FilterOption(id: t.name, label: t.name),
  ];

  return FilterSpec(
    title: 'Filter members',
    sections: [
      const FilterSection(title: 'Status', fields: [
        FilterField(
          id: 'statuses',
          label: 'Status',
          control: FilterControl.checkboxGroup,
          options: [
            FilterOption(id: 'active', label: 'Active'),
            FilterOption(id: 'invited', label: 'Invited'),
            FilterOption(id: 'inactive', label: 'Inactive'),
          ],
        ),
      ]),
      FilterSection(title: 'Team', fields: [
        FilterField(
          id: 'teams',
          label: 'Team',
          control: FilterControl.checkboxGroup,
          twoCol: true,
          options: teamOpts,
        ),
      ]),
    ],
  );
}

/// Evaluate a member against applied filter values (mirrors the prototype's
/// `mmf.statuses` / `mmf.teams` list filters).
bool memberMatchesFilters(Member m, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('statuses'), [m.status])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('teams'), [m.team])) return false;
  return true;
}

// ── Providers ──

/// The Members drawer spec, derived from the loaded team catalog.
final membersFilterSpecProvider = Provider<FilterSpec>((ref) {
  final teams = ref.watch(teamsProvider).valueOrNull ?? const [];
  return buildMembersFilterSpec(teams);
});

/// Applied drawer filters for the Members list (the source of the badge count).
final memberFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Members list (bookmark chips).
final memberSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());

/// The Members list with the role tab + search ([visibleMembersProvider]) AND
/// the applied drawer filters applied. The screen renders this.
final filteredMembersProvider = Provider<List<Member>>((ref) {
  final base = ref.watch(visibleMembersProvider);
  final filters = ref.watch(memberFiltersProvider);
  if (filters.isEmpty) return base;
  return base.where((m) => memberMatchesFilters(m, filters)).toList();
});
