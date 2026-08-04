import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/storage/app_cache.dart';
import '../../features/auth/application/providers/auth_providers.dart';
import '../app.dart';

/// Starts the app inside a [ProviderScope]. This is the single place where
/// infrastructure is initialized (Hive cache, session restore) and where
/// tests inject overrides (e.g. fake repositories).
Future<void> bootstrap({List<Override> overrides = const []}) async {
  WidgetsFlutterBinding.ensureInitialized();

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
}
