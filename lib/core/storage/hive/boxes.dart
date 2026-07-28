/// Every Hive box name in the app, in one place.
///
/// Flutter Coding Standards §3.1: box names are clear and feature-based —
/// never `box1` or `myBox`. The lint rule `HiveBoxesDeclarationRule` requires
/// `static const String`, a camelCase identifier and a snake_case value.
///
/// Adding a box here and to [all] is the only supported way to introduce one,
/// so startup and logout both stay complete by construction.
class HiveBoxes {
  const HiveBoxes._();

  /// Signed-in user profile and workspace metadata.
  ///
  /// Session tokens do NOT belong here — see `SecureStoreKeys`.
  static const String authBox = 'auth';

  /// User preferences and non-sensitive app settings.
  static const String settingsBox = 'settings';

  /// Cached CRM records: leads, customers, follow-ups, quotes, invoices.
  static const String crmCacheBox = 'crm_cache';

  /// Cached operations records: projects and operations tasks.
  static const String opsCacheBox = 'ops_cache';

  /// Cached helpdesk tickets and board state.
  static const String helpdeskCacheBox = 'helpdesk_cache';

  /// Cached workspace roster: members, teams and roles.
  static const String peopleCacheBox = 'people_cache';

  /// Cached LMS courses and learner records.
  static const String trainingCacheBox = 'training_cache';

  /// Cached notification feed.
  static const String notificationsCacheBox = 'notifications_cache';

  /// Cached conversations and recent messages.
  static const String messagesCacheBox = 'messages_cache';

  /// Cached dashboard aggregates.
  static const String dashboardCacheBox = 'dashboard_cache';

  /// Every box, opened at startup and cleared on logout.
  static const List<String> all = [
    authBox,
    settingsBox,
    crmCacheBox,
    opsCacheBox,
    helpdeskCacheBox,
    peopleCacheBox,
    trainingCacheBox,
    notificationsCacheBox,
    messagesCacheBox,
    dashboardCacheBox,
  ];

  /// Boxes wiped on logout — everything except non-sensitive [settingsBox].
  ///
  /// QA.md security audit items 8 and 19: logout must delete cached user data.
  static const List<String> clearedOnLogout = [
    authBox,
    crmCacheBox,
    opsCacheBox,
    helpdeskCacheBox,
    peopleCacheBox,
    trainingCacheBox,
    notificationsCacheBox,
    messagesCacheBox,
    dashboardCacheBox,
  ];
}
