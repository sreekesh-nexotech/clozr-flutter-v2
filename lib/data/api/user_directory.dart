import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_service.dart';
import '../mock/mock_users.dart';

/// Bridges real API users onto the presentation layer's user model.
///
/// The UI was built against `MockUsers` and a `'me'` sentinel id
/// (`Lead.isMine`, avatar lookups, note authorship). Rather than rewriting
/// every screen, the remote mappers route user ids through here:
///
/// - [mapUserId] turns the signed-in user's uuid into `'me'` so all
///   "my records" logic keeps working.
/// - [register] adds real org members into `MockUsers.byId` (it is a mutable
///   map by design) so `MockUsers.of(uuid)` resolves names/initials/colours.
class UserDirectory {
  UserDirectory._();

  /// The signed-in user's uuid (set by the auth session controller).
  static String? currentUserId;

  /// Every uuid this directory has seen from the API.
  ///
  /// `MockUsers.byId` is seeded with the prototype reps and real users are
  /// registered into that same map, so membership there says nothing about
  /// whether a user exists on the server. This set does — it is what keeps the
  /// prototype's `am`/`rk`/`dr` ids out of pickers, and out of writes: the API
  /// rejects them outright (`"dr" is not a valid UUID`).
  static final Set<String> _apiIds = {};

  /// Bumped whenever the directory changes, so derived state can recompute.
  ///
  /// [_apiIds] and `MockUsers.byId` are plain mutable globals, which nothing
  /// downstream can watch. `rosterProvider` listens to this instead; without it
  /// the roster was computed once — against whatever the directory happened to
  /// hold at the first read — and cached for the rest of the session.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// A server user id, which is always a UUID.
  ///
  /// The prototype ids are two-letter codes (`am`, `rk`, `dr`), so shape alone
  /// separates them. Checked at the boundary in [register] and again in
  /// [realUserId]: one leak anywhere into [_apiIds] would otherwise make a
  /// prototype id look like a real user to every picker and every write, and a
  /// PATCH carrying `"assignees": ["dr"]` has been observed in the wild.
  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Whether [id] has the shape of a server user id.
  static bool isUuid(String? id) => id != null && _uuid.hasMatch(id);

  /// Whether [mappedId] refers to a user the server actually knows.
  static bool isApiUser(String? mappedId) {
    if (mappedId == null || mappedId.isEmpty) return false;
    if (mappedId == 'me') return currentUserId != null;
    return _apiIds.contains(mappedId);
  }

  static const List<Color> _palette = [
    AppColors.navy,
    AppColors.teal,
    AppColors.blueBright,
    AppColors.success,
    AppColors.pending,
    AppColors.warning,
    AppColors.navyMid,
  ];
  static int _colorSeq = 0;

  /// The inverse of [mapUserId]: the uuid to write for a picker's id.
  ///
  /// Every picker in the app deals in the mapped id, but a write needs the id
  /// the server knows — posting `'me'` as an owner is a validation error, and
  /// so is posting a prototype id like `'dr'`.
  ///
  /// Returns null for anything the server would reject, so a caller that skips
  /// nulls can never send an id the API has not confirmed exists.
  static String? realUserId(String? mappedId) {
    if (mappedId == null || mappedId.isEmpty) return null;
    final id = mappedId == 'me' ? currentUserId : mappedId;
    if (id == null || id.isEmpty) return null;
    // Shape as well as membership. Belt and braces on the write path: the set
    // is filled from a dozen mappers, and a single one registering something
    // that is not a server id would otherwise put it on the wire.
    if (!isUuid(id)) return null;
    return (id == currentUserId || _apiIds.contains(id)) ? id : null;
  }

  /// `'me'` for the signed-in user, the uuid itself otherwise.
  static String mapUserId(String? userId) {
    if (userId == null || userId.isEmpty) return '';
    return userId == currentUserId ? 'me' : userId;
  }

  /// Registers one user into the shared directory. The signed-in user also
  /// refreshes the `'me'` entry so the drawer/notes show the real name.
  static void register({
    required String userId,
    required String fullName,
    String role = '',
  }) {
    if (userId.isEmpty || fullName.isEmpty) return;
    // Only a real server id may enter the set. A dozen mappers call in here
    // with whatever their row happened to hold, and everything downstream —
    // every picker's option list, every write that resolves an id — trusts
    // membership as proof the server knows the user.
    if (!isUuid(userId)) return;
    _apiIds.add(userId);
    final user = AppUser(
      id: mapUserId(userId),
      name: fullName,
      initials: initialsOf(fullName),
      color: _palette[_colorSeq++ % _palette.length],
      role: role.isEmpty ? 'Member' : role,
    );
    MockUsers.byId[user.id] = user;
    if (userId == currentUserId) {
      MockUsers.byId['me'] = AppUser(
        id: 'me',
        name: fullName,
        initials: initialsOf(fullName),
        color: AppColors.navy,
        role: role.isEmpty ? 'You' : '$role · You',
      );
    }
    revision.value++;
  }

  /// Registers an embedded API user object (`{user_id, full_name, ...}`).
  static void registerJson(Object? json) {
    if (json is! Map) return;
    final id = json['user_id'] as String? ?? '';
    final name = (json['full_name'] as String?) ??
        [json['first_name'], json['last_name']]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' ');
    register(userId: id, fullName: name);
  }

  /// Best-effort roster hydration from the members API. Non-admins may get a
  /// 403 — swallowed on purpose; embedded assignee objects on each record
  /// still register users lazily via [registerJson].
  static Future<void> hydrate(ApiService api) async {
    try {
      final body = await api.get(
        ApiEndpoints.users,
        query: {'page_size': 200},
      );
      if (body is Map<String, dynamic> && body['results'] is List) {
        for (final row in body['results'] as List) {
          if (row is Map) {
            register(
              userId: row['user_id'] as String? ?? '',
              fullName: row['full_name'] as String? ?? '',
              role: _roleOf(row),
            );
          }
        }
      }
    } on Object {
      // Roster is a nicety, never a blocker.
    }
  }

  static String _roleOf(Map row) {
    final role = row['role'];
    return role is Map ? (role['name'] as String? ?? '') : '';
  }

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return word.length >= 2 ? word.substring(0, 2).toUpperCase() : word.toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Clears session-specific state on logout. The known-user set goes with it:
  /// it is another tenant's roster to the next session.
  static void reset() {
    currentUserId = null;
    _apiIds.clear();
    // Drops the previous tenant's roster from every derived list, rather than
    // leaving their names on screen until something else happens to rebuild.
    revision.value++;
  }
}
