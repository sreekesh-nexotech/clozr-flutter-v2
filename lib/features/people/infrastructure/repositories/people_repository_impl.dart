import '../../../../app/config/constants.dart';
import '../../domain/entities/member.dart';
import '../../domain/entities/module_catalog.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/team.dart';
import '../../domain/repositories/people_repository.dart';
import '../data_sources/local/people_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class PeopleRepositoryImpl implements PeopleRepository {
  const PeopleRepositoryImpl(this._local);

  final PeopleMockDataSource _local;

  @override
  Future<List<Member>> getMembers() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchMembers();
  }

  @override
  Future<List<Team>> getTeams() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchTeams();
  }

  @override
  Future<List<Role>> getRoles() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchRoles();
  }

  // ── Writes: harmless local echoes so mock mode keeps working ──

  @override
  Future<void> inviteMember({
    required String email,
    required String name,
    String? phone,
    String? roleId,
    String? managerId,
  }) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    // Mock mode: toast-only — the seed roster is immutable.
  }

  @override
  Future<Team?> createTeam({
    required String name,
    String? description,
    String? leadUserId,
    List<String> memberIds = const [],
  }) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return Team(
      id: 'team-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      zone: description ?? '',
      lead: leadUserId ?? '',
      members: memberIds,
    );
  }

  @override
  Future<void> updateTeam(String id, Map<String, dynamic> fields) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    // Mock mode: toast-only — the seed teams are immutable.
  }

  @override
  Future<void> addTeamMembers({
    required String teamId,
    required List<String> userIds,
  }) async {
    await Future<void>.delayed(AppConstants.mockLatency);
  }

  /// Mock mode has no catalog endpoint; empty sends the form to its built-in
  /// card set, which is the same one the API serves today.
  @override
  Future<ModuleCatalog> getModuleCatalog() async => ModuleCatalog.empty;

  @override
  Future<void> createRole({
    required String name,
    String? description,
    Set<String> groups = const {},
    String visibility = 'hierarchy',
  }) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    // Mock mode: toast-only — the seed role list is immutable.
  }

  @override
  Future<void> updateMember(
    String userId, {
    String? name,
    String? email,
    String? phone,
    String? roleId,
    String? managerId,
  }) async {
    await Future<void>.delayed(AppConstants.mockLatency);
  }

  @override
  Future<void> updateRole(
    String id, {
    required String name,
    String? description,
    Set<String> groups = const {},
    String visibility = 'hierarchy',
  }) async {
    await Future<void>.delayed(AppConstants.mockLatency);
  }

  @override
  Future<void> deleteRole(String id) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    // Mock mode: toast-only — the seed role list is immutable.
  }

  /// The seed members already carry their performance figures.
  @override
  Future<Member> withPerformance(Member member, {String period = 'all_time'}) async =>
      member;

  /// No activity feed in the seed data; the card falls back to its derived rows.
  @override
  Future<List<MemberActivity>> getMemberActivity(String userId) async => const [];

  /// No retrieve endpoint in mock mode; the seed row is all there is.
  @override
  Future<Member?> getMember(String userId) async => null;
}
