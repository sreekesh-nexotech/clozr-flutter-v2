import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../network/app_error.dart';

/// Compile-time crash-reporting configuration, in the same `--dart-define`
/// style `ApiConfig` uses for the backend.
///
/// A Sentry DSN is a public identifier (it only grants *write* access to the
/// project's event ingest), so it ships in source like any other endpoint.
/// It stays overridable per build all the same:
///
/// ```sh
/// flutter build apk --release \
///   --dart-define=SENTRY_ENVIRONMENT=production \
///   --dart-define=SENTRY_RELEASE=clozr@1.0.0+1
/// ```
///
/// Passing an **empty** DSN switches reporting off without removing the SDK —
/// `SentryFlutter.init` still runs, still starts the app, and simply drops
/// every event. That is the kill switch:
///
/// ```sh
/// flutter run --dart-define=SENTRY_DSN=
/// ```
class SentryConfig {
  SentryConfig._();

  /// Ingest endpoint for the `clozr` Sentry project.
  static const String dsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue:
        'https://c920df786f8f8456d2e2ce03a0c8b895@o4510509677608960.ingest.us.sentry.io/4511868002828288',
  );

  /// Segregates issues in the Sentry UI. Defaults follow the build mode so a
  /// developer's stack traces never land in the production issue stream.
  static const String environment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: kReleaseMode
        ? 'production'
        : kProfileMode
            ? 'profile'
            : 'development',
  );

  /// Groups issues by build, e.g. `clozr@1.0.0+1`. Left empty the SDK derives
  /// it from the package metadata, which is right for local builds; CI should
  /// pass the same value it uploads debug symbols under.
  static const String release = String.fromEnvironment('SENTRY_RELEASE');

  /// Share of transactions kept for performance monitoring, as a percentage.
  /// Full sampling while developing, a fifth of production traffic in release
  /// — enough to see p95 latency without paying for every request.
  static const int tracesSamplePercent = int.fromEnvironment(
    'SENTRY_TRACES_SAMPLE_PCT',
    defaultValue: kReleaseMode ? 20 : 100,
  );

  static bool get enabled => dsn.isNotEmpty;

  static double get tracesSampleRate => tracesSamplePercent.clamp(0, 100) / 100;

  /// The one place `SentryFlutter.init` is configured. Passed to `init` as the
  /// options callback so nothing else in the app touches [SentryFlutterOptions].
  static void apply(SentryFlutterOptions options) {
    options
      ..dsn = dsn
      ..environment = environment
      ..tracesSampleRate = tracesSampleRate
      // The SDK's own console logging — noisy, and only ever useful while
      // wiring reporting up.
      ..debug = false
      // Hard off. This app is a CRM: request bodies, headers and URLs carry
      // customer records and bearer tokens, and `sendDefaultPii` is what tells
      // sentry_dio to attach them. [_beforeSend] scrubs anything that slips
      // past this as a second line of defence.
      ..sendDefaultPii = false
      // Screenshots and the widget tree render customer data on screen, so
      // both stay off for the same reason.
      ..attachScreenshot = false
      ..attachViewHierarchy = false
      // 5xx responses raised by the ApiService Dio become issues; 4xx are the
      // backend answering correctly and are already surfaced to the user.
      ..captureFailedRequests = true
      ..beforeSend = _beforeSend;

    if (release.isNotEmpty) options.release = release;
  }

  /// Headers that must never reach Sentry. Compared lower-cased — HTTP header
  /// names are case-insensitive and Dio preserves whatever casing was set.
  static const Set<String> _redactedHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-csrftoken',
  };

  /// Drops noise and strips credentials before an event leaves the device.
  static SentryEvent? _beforeSend(SentryEvent event, Hint hint) {
    if (isExpectedFailure(event.throwable)) return null;

    final request = event.request;
    if (request == null) return event;

    // Rebuilt rather than `request.copyWith`-ed: copyWith falls back to the
    // old value for anything passed as null, so it cannot *drop* a field —
    // and dropping `data` is the whole point.
    return event.copyWith(
      request: SentryRequest(
        url: request.url,
        method: request.method,
        queryString: request.queryString,
        fragment: request.fragment,
        apiTarget: request.apiTarget,
        env: request.env,
        // `data` is deliberately not carried over: on the auth routes the
        // request body *is* the password / OTP / refresh token, and on every
        // other route it is customer data.
        headers: {
          for (final header in request.headers.entries)
            if (!_redactedHeaders.contains(header.key.toLowerCase()))
              header.key: header.value,
        },
      ),
    );
  }

  /// Whether a failure is a normal operating condition rather than a defect.
  ///
  /// A user on a train loses connectivity, a session expires, a form fails
  /// validation — the app already handles and explains all three. Reporting
  /// them would bury real crashes under thousands of events, so they are
  /// filtered here rather than at each call site.
  static bool isExpectedFailure(Object? error) {
    if (error is! AppError) return false;
    return const {
      AppErrorType.network,
      AppErrorType.timeout,
      AppErrorType.cancelled,
      AppErrorType.unauthorized,
      AppErrorType.forbidden,
      AppErrorType.notFound,
      AppErrorType.validation,
    }.contains(error.type);
  }
}
