import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/member.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/team.dart';
import '../../domain/repositories/people_repository.dart';
import '../data_sources/remote/people_remote_ds.dart';

/// API-backed [PeopleRepository]. Reads go remote-first and fall back to the
/// Hive cache when the network is down; writes are remote-only and drop the
/// stale list key so the next read refetches.
class PeopleApiRepository implements PeopleRepository {
  const PeopleApiRepository(this._remote);

  final PeopleRemoteDataSource _remote;

  static const String _box = AppCache.peopleCache;
  static const String _membersKey = 'members';
  static const String _teamsKey = 'teams';
  static const String _rolesKey = 'roles';

  @override
  Future<List<Member>> getMembers() async {
    final rows = await _rowsWithFallback(_membersKey, _remote.fetchMemberRows);
    return PeopleRemoteDataSource.membersFromRows(rows);
  }

  @override
  Future<List<Team>> getTeams() async {
    List<dynamic> teamRows;
    List<dynamic> memberRows;
    try {
      teamRows = await _remote.fetchTeamRows();
      memberRows = await _remote.fetchTeamMemberRows();
      await AppCache.put(_box, _teamsKey, {
        'teams': teamRows,
        'team_members': memberRows,
      });
    } on AppError catch (e) {
      if (!_isOffline(e)) rethrow;
      final data = AppCache.get(_box, _teamsKey)?.data;
      if (data is! Map) rethrow;
      teamRows = data['teams'] as List? ?? const [];
      memberRows = data['team_members'] as List? ?? const [];
    }

    final grouped = PeopleRemoteDataSource.groupTeamMembers(memberRows);
    final teams = <Team>[];
    for (final row in teamRows) {
      if (row is! Map<String, dynamic>) continue;
      final team = PeopleRemoteDataSource.teamFromJson(row, grouped);
      if (team != null) teams.add(team);
    }
    return teams;
  }

  @override
  Future<List<Role>> getRoles() async {
    final rows = await _rowsWithFallback(_rolesKey, _remote.fetchRoleRows);
    final roles = <Role>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final role = PeopleRemoteDataSource.roleFromJson(row);
      if (role != null) roles.add(role);
    }
    return roles;
  }

  @override
  Future<void> inviteMember({
    required String email,
    required String name,
    String? phone,
    String? roleId,
  }) async {
    await _remote.inviteMember(
      email: email,
      name: name,
      phone: phone,
      roleId: roleId,
    );
    await AppCache.remove(_box, _membersKey);
  }

  @override
  Future<Team?> createTeam({
    required String name,
    String? description,
    String? leadUserId,
  }) async {
    final team = await _remote.createTeam(
      name: name,
      description: description,
      leadUserId: leadUserId,
    );
    await AppCache.remove(_box, _teamsKey);
    return team;
  }

  @override
  Future<void> createRole({required String name, String? description}) async {
    await _remote.createRole(name: name, description: description);
    await AppCache.remove(_box, _rolesKey);
  }

  /// Remote-first read of raw rows: success refreshes the cache; a
  /// network/timeout failure serves the cached copy when present.
  Future<List<dynamic>> _rowsWithFallback(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    try {
      final rows = await fetch();
      await AppCache.put(_box, key, rows);
      return rows;
    } on AppError catch (e) {
      if (!_isOffline(e)) rethrow;
      final data = AppCache.get(_box, key)?.data;
      if (data is List) return data;
      rethrow;
    }
  }

  static bool _isOffline(AppError e) =>
      e.type == AppErrorType.network || e.type == AppErrorType.timeout;
}
