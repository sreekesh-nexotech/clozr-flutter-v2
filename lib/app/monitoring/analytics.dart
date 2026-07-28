import '../config/feature_flags.dart';
import '../../core/utils/logger.dart';

/// Destination for analytics events.
///
/// Implement once per backend (Firebase, Segment, …) and install it with
/// [Analytics.install]. Keeping the app behind this interface means swapping
/// providers never touches a feature.
abstract interface class AnalyticsSink {
  /// Records a named event with optional [parameters].
  Future<void> logEventAsync(String name, {Map<String, Object?> parameters});

  /// Associates subsequent events with a user.
  ///
  /// Pass the opaque user id only — never a name, email or phone number.
  Future<void> setUserIdAsync(String? userId);
}

/// An [AnalyticsSink] that logs locally and sends nothing.
///
/// The default, so calling [Analytics.track] before a real sink is installed
/// is always safe.
class NoopAnalyticsSink implements AnalyticsSink {
  /// Creates the no-op sink.
  const NoopAnalyticsSink();

  @override
  Future<void> logEventAsync(
    String name, {
    Map<String, Object?> parameters = const {},
  }) async {
    AppLogger.debug('analytics event (not sent): $name $parameters');
  }

  @override
  Future<void> setUserIdAsync(String? userId) async {
    AppLogger.debug('analytics user id (not sent): $userId');
  }
}

/// Canonical event names.
///
/// Named constants rather than inline strings so a typo cannot silently split
/// a funnel (`MagicStringDetectionRule`).
class AnalyticsEvents {
  const AnalyticsEvents._();

  /// A screen became visible.
  static const String screenView = 'screen_view';

  /// A lead was created.
  static const String leadCreated = 'lead_created';

  /// A lead's status changed.
  static const String leadStatusChanged = 'lead_status_changed';

  /// A quote was created.
  static const String quoteCreated = 'quote_created';

  /// A payment was recorded.
  static const String paymentRecorded = 'payment_recorded';

  /// A helpdesk ticket was created.
  static const String ticketCreated = 'ticket_created';

  /// An operations task was completed.
  static const String taskCompleted = 'task_completed';

  /// A search was run from a list screen.
  static const String searchPerformed = 'search_performed';
}

/// App-wide analytics facade.
///
/// Fire-and-forget by design: analytics must never block or break a user
/// action, so failures are swallowed after being logged.
class Analytics {
  const Analytics._();

  static AnalyticsSink _sink = const NoopAnalyticsSink();

  /// Replaces the active sink. Call once during bootstrap.
  static void install(AnalyticsSink sink) => _sink = sink;

  /// Records [name] with optional [parameters], honouring
  /// [FeatureFlags.enableAnalytics].
  static Future<void> trackAsync(
    String name, {
    Map<String, Object?> parameters = const {},
  }) async {
    if (!FeatureFlags.enableAnalytics) return;
    try {
      await _sink.logEventAsync(name, parameters: parameters);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Analytics event "$name" failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Associates subsequent events with [userId], or clears it on logout.
  static Future<void> setUserIdAsync(String? userId) async {
    if (!FeatureFlags.enableAnalytics) return;
    try {
      await _sink.setUserIdAsync(userId);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Analytics user id failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
