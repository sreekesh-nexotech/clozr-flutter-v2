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
}
