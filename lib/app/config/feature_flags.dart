/// Central switches for staged rollouts and experiments.
///
/// Read these in providers and UI to gate a feature; never scatter
/// `if (kDebugMode)` checks through widgets. Every flag carries the reason it
/// exists so dead ones are easy to spot and delete.
///
/// These are compile-time defaults. When remote config lands, keep this class
/// as the single read point and have it fall back to these values.
class FeatureFlags {
  const FeatureFlags._();

  /// Serve cached Hive data before the network responds.
  ///
  /// Off until the caching layer is implemented.
  static const bool enableOfflineCache = false;

  /// Queue writes made while offline and replay them on reconnect.
  ///
  /// Off until conflict handling is specified.
  static const bool enableOfflineWriteQueue = false;

  /// Show the Rewards module in the drawer and bottom nav.
  static const bool enableRewards = true;

  /// Show the Training (LMS) module.
  static const bool enableTraining = true;

  /// Show the Messages module.
  static const bool enableMessages = true;

  /// Allow raising invoices and recording payments from the app.
  ///
  /// Off until the payment gateway integration is signed off.
  static const bool enableBilling = false;

  /// Deliver push notifications.
  ///
  /// Off until device-token registration is implemented.
  static const bool enablePushNotifications = false;

  /// Emit analytics events.
  static const bool enableAnalytics = false;

  /// Expose the in-app diagnostics screen (environment, build, log buffer).
  static const bool enableDiagnostics = false;
}
