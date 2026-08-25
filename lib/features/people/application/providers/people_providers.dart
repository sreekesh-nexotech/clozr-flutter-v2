import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/member.dart';
import '../../domain/entities/module_catalog.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/team.dart';
import '../../domain/repositories/people_repository.dart';
import '../../infrastructure/data_sources/local/people_mock_ds.dart';
import '../../infrastructure/data_sources/remote/people_remote_ds.dart';
import '../../infrastructure/repositories/people_api_repository.dart';
import '../../infrastructure/repositories/people_repository_impl.dart';

/// DI seam: API-backed when a base URL is configured, mock otherwise.
final peopleRepositoryProvider = Provider<PeopleRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const PeopleRepositoryImpl(PeopleMockDataSource());
  }
  return PeopleApiRepository(
    PeopleRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

// ── Async sources ──

final membersProvider = FutureProvider<List<Member>>(
  (ref) => ref.watch(peopleRepositoryProvider).getMembers(),
);

final teamsProvider = FutureProvider<List<Team>>(
  (ref) => ref.watch(peopleRepositoryProvider).getTeams(),
);

final rolesProvider = FutureProvider<List<Role>>(
  (ref) => ref.watch(peopleRepositoryProvider).getRoles(),
);

/// The capability cards and visibility scopes the Add role form offers.
///
/// A static code registry on the backend, so it is fetched once per session.
/// Empty (mock mode, a failed fetch) is the form's signal to use
/// [ModuleCatalog.builtIn] rather than to block role creation.
final moduleCatalogProvider = FutureProvider<ModuleCatalog>(
  (ref) => ref.watch(peopleRepositoryProvider).getModuleCatalog(),
);

/// Member lookup by id, keyed map — used by the team cards to resolve a lead /
/// member's name, initials and colour.
final membersByIdProvider = Provider<Map<String, Member>>((ref) {
  final members = ref.watch(membersProvider).valueOrNull ?? const [];
  return {for (final m in members) m.id: m};
});

/// Look up a single member by id (used by the detail screen).
final memberByIdProvider = Provider.family<Member?, String>((ref, id) {
  return ref.watch(membersByIdProvider)[id];
});

/// One member from `GET /management/users/{id}/`, carrying the detail-only
/// fields the paginated list omits — `scope`, `is_protected`,
/// `profile.designation`, `profile.timezone`, `territories` (`members.md` §4.1).
///
/// The detail screen used to read only the list row, which is why Designation
/// showed the role name, Role & scope always ended in "—", and Territory and
/// Timezone were hardcoded strings.
///
/// Null while in flight, in mock mode, and on failure; the caller keeps the
/// list row.
final memberDetailProvider =
    FutureProvider.autoDispose.family<Member?, String>((ref, id) {
  if (id.isEmpty) return Future.value(null);
  ref.watch(apiWriteTickProvider);
  return ref.watch(peopleRepositoryProvider).getMember(id);
});

/// The fullest member available: the enriched record once it lands, the list
/// row until then. Read this on the detail screen.
final memberDetailOrListProvider = Provider.autoDispose.family<Member?, String>(
  (ref, id) =>
      ref.watch(memberDetailProvider(id)).valueOrNull ??
      ref.watch(memberByIdProvider(id)),
);

/// One member with their owned-lead metrics filled in
/// (`GET /crm/dashboard-crm/member-performance/`, `members.md` §4.2).
///
/// Kept off the list on purpose: the figures are one call **per member**, so
/// fetching them for the roster would be an N+1. The detail screen asks for the
/// one member it is showing.
///
/// Falls back to the plain member — with the entity's zero defaults — in mock
/// mode and whenever the caller lacks `can_access_user_kpis`, which 403s.
final memberWithPerformanceProvider =
    FutureProvider.autoDispose.family<Member?, String>((ref, id) async {
  final member = ref.watch(memberDetailOrListProvider(id));
  if (member == null) return null;
  // Watched, so changing the range re-queries rather than re-slicing figures
  // the server already aggregated.
  return ref
      .watch(peopleRepositoryProvider)
      .withPerformance(member, period: ref.watch(memberPerfPeriodProvider));
});

/// The Performance & records range, as the API's own `period` value.
///
/// Every option below is verified against `/dashboard-crm/member-performance/`.
/// `all_time` stays the default — it is what the card showed before the control
/// did anything.
final memberPerfPeriodProvider = StateProvider<String>((ref) => 'all_time');

/// The range options, in the order the sheet lists them: `(api value, label)`.
const kMemberPerfPeriods = <(String, String)>[
  ('all_time', 'All time'),
  ('this_month', 'This month'),
  ('last_month', 'Last month'),
  ('this_quarter', 'This quarter'),
  ('last_quarter', 'Previous quarter'),
  ('year', 'This year'),
  ('last_30_days', 'Last 30 days'),
  ('last_90_days', 'Last 90 days'),
];

/// The label for a stored period value; falls back to "All time" so an unknown
/// value never renders a blank chip.
String memberPerfPeriodLabel(String value) {
  for (final (v, label) in kMemberPerfPeriods) {
    if (v == value) return label;
  }
  return 'All time';
}

/// One member's activity feed (`GET /management/users/{id}/activity/`).
///
/// Empty in mock mode, and for a role without `view_user_management` — the card
/// then keeps its derived rows rather than rendering nothing.
final memberActivityProvider =
    FutureProvider.autoDispose.family<List<MemberActivity>, String>((ref, id) {
  if (id.isEmpty) return Future.value(const []);
  ref.watch(apiWriteTickProvider);
  return ref.watch(peopleRepositoryProvider).getMemberActivity(id);
});

// ── Members list UI state ──

/// The built-in role vocabulary, used **only** until the org's own arrives.
///
/// A fallback, not the source of truth: these are the prototype's five names,
/// and the tab row matches a member's `role.name` exactly — so a tab whose name
/// the org does not use filters to nothing, and a role it does use has no tab
/// at all. [memberRoleTabsProvider] prefers the real catalog.
const memberRoleOrder = <String>[
  'System Admin',
  'Executive Leadership',
  'Manager',
  'Sales executive',
  'Viewer',
];

/// The role names the tab row renders: the org's own roles
/// (`GET /management/roles/`, already fetched by [rolesProvider]) in the order
/// the server returned them, falling back to [memberRoleOrder] in mock mode,
/// while the fetch is in flight, and if it fails.
///
/// The catalog was being fetched and then ignored here, which is what left the
/// tabs on the prototype vocabulary.
final memberRoleTabsProvider = Provider<List<String>>((ref) {
  final roles = ref.watch(rolesProvider).valueOrNull ?? const [];
  final names = [
    for (final r in roles)
      if (r.name.trim().isNotEmpty) r.name.trim(),
  ];
  return names.isEmpty ? memberRoleOrder : names;
});

/// Active role tab on the Members list ('all' or a role name).
final memberRoleProvider = StateProvider<String>((ref) => 'all');

/// The role tab actually in force.
///
/// The catalog can land *after* the user has picked one of the built-in names,
/// and the org may not have that role — which would leave the row with nothing
/// selected and the list empty for a reason no one could see. A selection that
/// is no longer offered falls back to "all". Read this rather than
/// [memberRoleProvider] anywhere the choice is applied or drawn, so the chip
/// and the list can never disagree.
final effectiveMemberRoleProvider = Provider<String>((ref) {
  final role = ref.watch(memberRoleProvider);
  if (role == 'all') return 'all';
  return ref.watch(memberRoleTabsProvider).contains(role) ? role : 'all';
});

/// Search query on the Members list.
final memberSearchProvider = StateProvider<String>((ref) => '');

/// Whether the Members search field is expanded.
final memberSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Members filtered by the active role tab + search query.
final visibleMembersProvider = Provider<List<Member>>((ref) {
  final members = ref.watch(membersProvider).valueOrNull ?? const [];
  final role = ref.watch(effectiveMemberRoleProvider);
  final q = ref.watch(memberSearchProvider).trim().toLowerCase();

  Iterable<Member> out = members;
  if (role != 'all') out = out.where((m) => m.role == role);
  if (q.isNotEmpty) {
    out = out.where((m) =>
        m.name.toLowerCase().contains(q) ||
        m.email.toLowerCase().contains(q) ||
        m.team.toLowerCase().contains(q));
  }
  return out.toList();
});

/// Count of members for a given role tab key.
int memberRoleCount(List<Member> members, String key) {
  if (key == 'all') return members.length;
  return members.where((m) => m.role == key).length;
}

// ── Teams list UI state ──

/// Search query on the Teams list.
final teamSearchProvider = StateProvider<String>((ref) => '');

/// Whether the Teams search field is expanded.
final teamSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Teams filtered by the search query (team name, lead name, member names).
final visibleTeamsProvider = Provider<List<Team>>((ref) {
  final teams = ref.watch(teamsProvider).valueOrNull ?? const [];
  final byId = ref.watch(membersByIdProvider);
  final q = ref.watch(teamSearchProvider).trim().toLowerCase();
  if (q.isEmpty) return teams;

  return teams.where((t) {
    final lead = byId[t.lead]?.name ?? '';
    final memberNames = t.members.map((id) => byId[id]?.name ?? '').join(' ');
    return '${t.name} $lead $memberNames'.toLowerCase().contains(q);
  }).toList();
});
