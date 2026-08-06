import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/models/note.dart';
import '../mock/mock_users.dart';

/// The list of workspace users offered in owner/assignee filters and pickers.
///
/// In mock mode this is the fixed prototype roster (`MockUsers.reps`). In API
/// mode it is the real org members that have been registered into
/// `MockUsers.byId` — from `UserDirectory.hydrate` (GET /management/users/) and
/// from assignee/owner objects embedded in loaded records — so pickers never
/// offer the fake prototype reps against a live backend. Excludes the neutral
/// "Unknown" placeholder.
final rosterProvider = Provider<List<AppUser>>((ref) {
  if (!ApiConfig.apiEnabled) return MockUsers.reps;
  final users = MockUsers.byId.values
      .where((u) => u.name.isNotEmpty && u.name != 'Unknown')
      .toList();
  // Keep the signed-in user first for a stable, familiar ordering.
  users.sort((a, b) => a.id == 'me'
      ? -1
      : b.id == 'me'
          ? 1
          : a.name.compareTo(b.name));
  return users;
});

/// The signed-in user as a notes byline — the composer avatar, and the author
/// on a note you just wrote.
///
/// Reads `MockUsers['me']`, which the auth session overwrites with the real
/// account on sign-in (`UserDirectory.register` from `_adoptUser`). That
/// happens before any screen opens and does not depend on the roster fetch
/// succeeding, so it holds even for a user who cannot list org members.
/// In mock mode it stays the prototype user, which is correct there.
final noteAuthorProvider = Provider<NoteAuthor>((ref) {
  final me = MockUsers.of('me');
  return NoteAuthor(initials: me.initials, name: me.name, color: me.color);
});
