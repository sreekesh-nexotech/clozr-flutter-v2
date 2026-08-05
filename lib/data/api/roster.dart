import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
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
