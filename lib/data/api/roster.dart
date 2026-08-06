import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/models/note.dart';
import '../mock/mock_users.dart';
import 'user_directory.dart';

/// The list of workspace users offered in owner/assignee filters and pickers.
///
/// In mock mode this is the fixed prototype roster (`MockUsers.reps`). In API
/// mode it is the real org members registered into `MockUsers.byId` — from
/// `UserDirectory.hydrate` (GET /management/users/) and from assignee/owner
/// objects embedded in loaded records. Excludes the neutral "Unknown"
/// placeholder.
///
/// The API-mode filter goes through [UserDirectory.isApiUser] rather than
/// simply reading `MockUsers.byId`: that map is **seeded** with the prototype
/// reps and real users are registered into the same map, so its contents alone
/// cannot tell the two apart. Without the check the pickers offered names like
/// "Divya Rao" against a live backend, and choosing one sent the prototype id
/// `dr` to the API — which rejects it (`"dr" is not a valid UUID`).
final rosterProvider = Provider<List<AppUser>>((ref) {
  if (!ApiConfig.apiEnabled) return MockUsers.reps;
  final users = MockUsers.byId.values
      .where((u) =>
          u.name.isNotEmpty &&
          u.name != 'Unknown' &&
          UserDirectory.isApiUser(u.id))
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
