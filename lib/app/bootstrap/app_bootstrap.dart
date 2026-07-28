import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';

/// Starts the app inside a [ProviderScope]. This is the single place to inject
/// global overrides (e.g. swapping mock data sources for real API clients when
/// the infrastructure layer lands) and to register error hooks.
void bootstrap({List<Override> overrides = const []}) {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO(api): open Hive boxes / register adapters here when caching lands.

  runApp(
    ProviderScope(
      overrides: overrides,
      child: const ClozrApp(),
    ),
  );
}
