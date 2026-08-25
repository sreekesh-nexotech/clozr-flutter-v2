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
FilterSpec buildMembersFilterSpec(
  List<Team> teams, {
  List<Member> members = const [],
}) {
  final teamOpts = [
    for (final t in teams) FilterOption(id: t.name, label: t.name),
  ];

  // "Any manager" (`members.md` Part 1 — the `manager_id` facet). Any org user
  // can be a manager, so the options are the people actually managing someone
  // rather than the whole roster: a name nobody reports to would only ever
  // match nothing.
  //
  // Keyed by the manager's **`user_id`**, which is the identity the doc uses.
  // Keying by `full_name` collapsed two managers who share a name into one
  // option that matched both of them.
  final managerNames = <String, String>{};
  for (final m in members) {
    if (!m.hasManager || m.managerId.isEmpty) continue;
    managerNames[m.managerId] = m.reportsTo.trim();
  }
  final managerOpts = [
    for (final e in managerNames.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase())))
      FilterOption(id: e.key, label: e.value),
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
            FilterOption(id: 'inactive', label: 'Deactivated'),
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
      // Dropped entirely when nobody has a manager — an empty searchable
      // section is worse than no section.
      if (managerOpts.isNotEmpty)
        FilterSection(title: 'Reports to', fields: [
          FilterField(
            id: 'managers',
            label: 'Reporting manager',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search manager…',
            options: managerOpts,
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
  // Matched on the manager's uuid, the same identity the options are keyed by.
  // A member with no manager matches nothing rather than everything — the
  // sentinel "— (exempt)" is not a manager anyone can be filtered by.
  //
  // Only the *current* manager counts: the API says a closed or historical
  // reporting relationship does not match, and the row carries only the
  // present one.
  if (!FilterMatch.matchAnyOf(v.choice('managers'),
      m.hasManager && m.managerId.isNotEmpty ? [m.managerId] : const [])) {
    return false;
  }
  return true;
}

// ── Providers ──

/// The Members drawer spec, derived from the loaded team catalog.
final membersFilterSpecProvider = Provider<FilterSpec>((ref) {
  final teams = ref.watch(teamsProvider).valueOrNull ?? const [];
  return buildMembersFilterSpec(
    teams,
    members: ref.watch(membersProvider).valueOrNull ?? const [],
  );
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
