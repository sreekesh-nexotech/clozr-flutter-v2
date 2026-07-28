import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/member.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/team.dart';
import '../../domain/repositories/people_repository.dart';
import '../../infrastructure/data_sources/local/people_mock_ds.dart';
import '../../infrastructure/repositories/people_repository_impl.dart';

/// DI seam: override this in `bootstrap` to inject a real API-backed repo.
final peopleRepositoryProvider = Provider<PeopleRepository>(
  (ref) => const PeopleRepositoryImpl(PeopleMockDataSource()),
);

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

// ── Members list UI state ──

/// The ordered role filter tabs (prototype's `ROLETONE` key order).
const memberRoleOrder = <String>[
  'System Admin',
  'Executive Leadership',
  'Manager',
  'Sales executive',
  'Viewer',
];

/// Active role tab on the Members list ('all' or a role name).
final memberRoleProvider = StateProvider<String>((ref) => 'all');

/// Search query on the Members list.
final memberSearchProvider = StateProvider<String>((ref) => '');

/// Whether the Members search field is expanded.
final memberSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Members filtered by the active role tab + search query.
final visibleMembersProvider = Provider<List<Member>>((ref) {
  final members = ref.watch(membersProvider).valueOrNull ?? const [];
  final role = ref.watch(memberRoleProvider);
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
