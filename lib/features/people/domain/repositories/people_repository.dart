import '../entities/member.dart';
import '../entities/module_catalog.dart';
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

    /// The reporting manager's `user_id`. Sets the hierarchy row server-side;
    /// null leaves the member with no manager.
    String? managerId,
  });

  /// Creates a team. Returns the created team (member list still empty) or
  /// null when the response couldn't be read.
  Future<Team?> createTeam({
    required String name,
    String? description,
    String? leadUserId,
    List<String> memberIds = const [],
  });

  /// Edits a team, sending only [fields] the caller actually changed. Note that
  /// `member_ids` **replaces** the whole roster rather than adding to it.
  Future<void> updateTeam(String id, Map<String, dynamic> fields);

  /// Adds [userIds] to a team, one call each. Users already on the team are a
  /// no-op rather than an error.
  Future<void> addTeamMembers({required String teamId, required List<String> userIds});

  /// The capability cards and visibility scopes the Add role form offers.
  /// Empty when unavailable, which the form reads as "use the built-in set".
  Future<ModuleCatalog> getModuleCatalog();

  /// Creates a custom role granting [groups] (module-group keys) at
  /// [visibility] (a record-scope code such as `hierarchy`).
  Future<void> createRole({
    required String name,
    String? description,
    Set<String> groups,
    String visibility,
  });

  /// Edits a member (`PATCH /management/users/{id}/`). Only non-null fields are
  /// sent, so an untouched value is left as the server has it.
  ///
  /// Throws on refusal — a duplicate email is a `400` the form has to show.
  Future<void> updateMember(
    String userId, {
    String? name,
    String? email,
    String? phone,
    String? roleId,
    String? managerId,
  });

  /// Edits a **custom** role. [groups] replaces the capability set outright.
  ///
  /// Throws on refusal — a seeded role is a `403` and a duplicate name a `400`,
  /// and the form has to say which.
  Future<void> updateRole(
    String id, {
    required String name,
    String? description,
    Set<String> groups,
    String visibility,
  });

  /// Deletes a custom role.
  ///
  /// Throws on refusal — a seeded role is a `403` and a role that still has
  /// members a `409`, and the screen has to say which.
  Future<void> deleteRole(String id);

  /// One member's owned-lead metrics, overlaid onto [member].
  ///
  /// Returns the member unchanged when the figures are unavailable — mock mode,
  /// or a caller without `can_access_user_kpis`, which 403s. Performance is a
  /// nicety on the detail page, never a blocker.
  Future<Member> withPerformance(Member member, {String period = 'all_time'});

  /// One member's activity feed, newest first. Empty when unavailable.
  Future<List<MemberActivity>> getMemberActivity(String userId);

  /// One member from the **retrieve** endpoint, which carries the detail-only
  /// fields the list omits (scope, designation, timezone, territories,
  /// is_protected).
  ///
  /// Null when unavailable — mock mode, or a failed call — and the caller keeps
  /// the list row it already has.
  Future<Member?> getMember(String userId);
}
