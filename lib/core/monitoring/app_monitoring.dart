import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_config.dart';

/// The single crash-reporting gateway, mirroring the rule that keeps Dio behind
/// `ApiService`: feature code calls this class, never `Sentry` directly, so the
/// PII rules and the noise filter cannot be forgotten at a call site.
///
/// Every method is a no-op when reporting is disabled (empty DSN) or before
/// `SentryFlutter.init` has run, so callers need no guards.
class AppMonitoring {
  AppMonitoring._();

  /// Attaches the signed-in user to every subsequent event.
  ///
  /// Only the opaque user id and the org travel: a Sentry issue answers "who
  /// hit this and in which tenant" without the CRM's own address book being
  /// mirrored into a third-party service. The email/name are deliberately not
  /// sent — [SentryConfig] keeps `sendDefaultPii` off for the same reason.
  static Future<void> identify({
    required String userId,
    String? organizationId,
    String? organizationName,
  }) async {
    if (!Sentry.isEnabled || userId.isEmpty) return;
    await Sentry.configureScope((scope) async {
      await scope.setUser(SentryUser(id: userId));
      if (organizationId != null && organizationId.isNotEmpty) {
        scope.setContexts('organization', {
          'id': organizationId,
          if (organizationName != null && organizationName.isNotEmpty)
            'name': organizationName,
        });
      }
    });
  }

  /// Detaches the user on logout, so events from the login screen — or from the
  /// next person to sign in on a shared device — are not attributed to them.
  static Future<void> forget() async {
    if (!Sentry.isEnabled) return;
    await Sentry.configureScope((scope) async {
      await scope.setUser(null);
      scope.removeContexts('organization');
    });
  }

  /// Reports a caught error that the app recovered from but a developer should
  /// still see. Expected failures (offline, 401, validation) are dropped — see
  /// [SentryConfig.isExpectedFailure].
  static Future<void> captureError(
    Object error,
    StackTrace? stackTrace, {
    String? message,
  }) async {
    if (kDebugMode) {
      debugPrint('AppMonitoring.captureError${message == null ? '' : ' [$message]'}: $error');
    }
    if (!Sentry.isEnabled || SentryConfig.isExpectedFailure(error)) return;
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: message == null
          ? null
          : (scope) => scope.setContexts('detail', {'message': message}),
    );
  }

  /// Records a step in the trail that leads to a crash — the last few of these
  /// are attached to whatever event fires next.
  static void breadcrumb(
    String message, {
    String category = 'app',
    Map<String, dynamic>? data,
  }) {
    if (!Sentry.isEnabled) return;
    Sentry.addBreadcrumb(
      Breadcrumb(message: message, category: category, data: data),
    );
  }
}
