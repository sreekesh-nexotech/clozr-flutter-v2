import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/storage/app_cache.dart';
import '../../features/auth/application/providers/auth_providers.dart';
import '../app.dart';
import 'error_fallback.dart';

/// Starts the app inside a [ProviderScope]. This is the single place where
/// infrastructure is initialized (Hive cache, session restore), a top-level
/// error zone is installed, and where tests inject overrides.
Future<void> bootstrap({List<Override> overrides = const []}) async {
  // A branded fallback instead of the grey error box if a widget build throws.
  ErrorWidget.builder = (details) => const AppErrorFallback();

  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

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
      } on Object {
        // Cache is an optimization — a failed Hive init falls back to
        // network-only mode rather than blocking startup.
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
  }, (error, stack) {
    // Last-resort guard so an uncaught async error is logged, not swallowed
    // into a silent freeze.
    if (kDebugMode) {
      debugPrint('Uncaught zone error: $error');
    }
  });
}
