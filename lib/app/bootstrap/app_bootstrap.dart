import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/config/api_config.dart';
import '../../core/monitoring/app_monitoring.dart';
import '../../core/monitoring/sentry_config.dart';
import '../../core/services/in_app_update_service.dart';
import '../../core/storage/app_cache.dart';
import '../../features/auth/application/providers/auth_providers.dart';
import '../app.dart';
import 'error_fallback.dart';

/// Starts the app inside a [ProviderScope]. This is the single place where
/// infrastructure is initialized (crash reporting, Hive cache, session
/// restore), and where tests inject overrides.
///
/// [SentryFlutter.init] owns the top-level error handling that the hand-rolled
/// `runZonedGuarded` used to provide: it installs `FlutterError.onError`,
/// `PlatformDispatcher.onError` and the guarded zone around [_startApp], so an
/// uncaught async error is reported instead of vanishing into a silent freeze.
/// It runs the app either way — with an empty DSN the SDK simply drops every
/// event (see [SentryConfig]).
Future<void> bootstrap({List<Override> overrides = const []}) async {
  // A branded fallback instead of the grey error box if a widget build throws.
  ErrorWidget.builder = (details) => const AppErrorFallback();

  await SentryFlutter.init(
    SentryConfig.apply,
    appRunner: () => _startApp(overrides),
  );
}

Future<void> _startApp(List<Override> overrides) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every screen is a pixel-precise recreation of a portrait-only design
  // (fixed ScreenUtil sizing throughout, no landscape variant anywhere) — the
  // bottom nav and other fixed-height chrome overflow if the device rotates,
  // so the app declares its actual constraint instead of rendering broken.
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // Fail fast on an insecure production misconfiguration: a token-bearing
  // client must not talk cleartext to a non-local host.
  assert(
    !ApiConfig.apiEnabled || ApiConfig.isBaseUrlSecure,
    'API_BASE_URL must use https:// (got "${ApiConfig.baseUrl}"). '
    'Cleartext http is only allowed for local dev hosts.',
  );

  if (ApiConfig.apiEnabled) {
    try {
      await AppCache.init();
    } on Object catch (error, stack) {
      // Cache is an optimization — a failed Hive init falls back to
      // network-only mode rather than blocking startup. It is still worth
      // reporting: a device that cannot open its cache is a device where every
      // screen pays full network latency. Not awaited, so delivering the report
      // never delays first paint.
      unawaited(AppMonitoring.captureError(error, stack,
          message: 'AppCache.init failed'));
    }
  }

  final container = ProviderContainer(overrides: overrides);

  // Kick off session restore (token load → /me refresh → roster hydration).
  // In mock mode this simply marks the session authenticated.
  container.read(sessionControllerProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ClozrApp(),
    ),
  );

  // Not awaited: a Play Store check has no bearing on first paint, and an
  // immediate update takes over the screen with its own UI whenever it does
  // resolve — there is nothing here for the app to wait on.
  unawaited(InAppUpdateService.checkAndPrompt());
}
