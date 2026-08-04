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

  /// Clears session-specific state on logout.
  static void reset() {
    currentUserId = null;
  }
}
