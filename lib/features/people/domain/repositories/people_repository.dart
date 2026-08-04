import '../entities/member.dart';
import '../entities/role.dart';
import '../entities/team.dart';

/// Abstract contract for People data (members, teams, roles). The presentation
/// layer depends only on this; whether the data comes from a mock source or a
/// REST API is an infrastructure detail.
abstract class PeopleRepository {
  Future<List<Member>> getMembers();
  Future<List<Team>> getTeams();
  Future<List<Role>> getRoles();

  /// Invites a member by email. Server-side the user is created inactive and
  /// receives an activation email — the "Invited" status on the members list.
  Future<void> inviteMember({
    required String email,
    required String name,
    String? phone,
    String? roleId,
  });

  /// Creates a team. Returns the created team (member list still empty) or
  /// null when the response couldn't be read.
  Future<Team?> createTeam({
    required String name,
    String? description,
    String? leadUserId,
  });

  /// Creates a custom role.
  Future<void> createRole({required String name, String? description});
}
