/// Keys used inside the Hive boxes declared in `boxes.dart`.
///
/// Centralised so no magic strings appear at call sites
/// (`MagicStringDetectionRule`) and so a rename is a single edit.
///
/// Nothing sensitive belongs here — tokens live in `SecureStoreKeys`.
class HiveKeys {
  const HiveKeys._();

  // ── auth box ──

  /// The signed-in user's id.
  static const String currentUserId = 'current_user_id';

  /// The cached user profile payload.
  static const String currentUserProfile = 'current_user_profile';

  /// The active workspace id.
  static const String workspaceId = 'workspace_id';

  /// Display name of the active workspace.
  static const String workspaceName = 'workspace_name';

  // ── settings box ──

  /// Selected locale tag, e.g. `en`.
  static const String localeTag = 'locale_tag';

  /// Whether the user opted into push notifications.
  static const String pushEnabled = 'push_enabled';

  /// Last dashboard period the user selected.
  static const String dashboardPeriod = 'dashboard_period';

  // ── *_cache boxes ──

  /// The cached collection payload for a resource.
  static const String records = 'records';

  /// When the cached collection was last written, as an ISO-8601 string.
  static const String lastSyncedAt = 'last_synced_at';

  /// Server-supplied cache validator (ETag) for conditional requests.
  static const String etag = 'etag';

  /// Builds the per-resource key for a cached collection.
  ///
  /// Example: `HiveKeys.recordsFor('leads')` → `records:leads`.
  static String recordsFor(String resource) => '$records:$resource';

  /// Builds the per-resource key for a sync timestamp.
  static String lastSyncedAtFor(String resource) => '$lastSyncedAt:$resource';
}
