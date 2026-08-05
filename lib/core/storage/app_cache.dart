import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Hive-backed JSON cache for final API results.
///
/// One box per feature (rule 3.1: clear, feature-based box names). Values are
/// stored as JSON strings with a written-at timestamp so repositories can
/// serve a stale copy when the network is down and refresh in the background.
/// Only repositories touch this class — never UI or providers.
class AppCache {
  AppCache._();

  static const String authBox = 'auth';
  static const String crmCache = 'crm_cache';
  static const String dashboardCache = 'dashboard_cache';
  static const String peopleCache = 'people_cache';
  static const String operationsCache = 'operations_cache';
  static const String helpdeskCache = 'helpdesk_cache';
  static const String notificationsCache = 'notifications_cache';
  static const String settingsBox = 'settings';

  static const List<String> _boxes = [
    authBox,
    crmCache,
    dashboardCache,
    peopleCache,
    operationsCache,
    helpdeskCache,
    notificationsCache,
    settingsBox,
  ];

  static bool _ready = false;

  /// Initializes Hive and opens every box. Called once from bootstrap; a
  /// failure falls through to network-only mode rather than crashing startup.
  static Future<void> init() async {
    if (_ready) return;
    await Hive.initFlutter();
    // Open boxes in parallel to shave startup latency.
    await Future.wait(_boxes.map((name) => Hive.openBox<String>(name)));
    _ready = true;
  }

  static bool get isReady => _ready;

  /// Writes [json] (any `jsonEncode`-able value) under [key] in [box].
  static Future<void> put(String box, String key, Object json) async {
    if (!_ready) return;
    final envelope = jsonEncode({
      'at': DateTime.now().toIso8601String(),
      'data': json,
    });
    await Hive.box<String>(box).put(key, envelope);
  }

  /// Reads the cached value for [key], or null when absent/corrupt or older
  /// than [maxAge].
  static CachedValue? get(String box, String key, {Duration? maxAge}) {
    if (!_ready) return null;
    final raw = Hive.box<String>(box).get(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.parse(decoded['at'] as String);
      if (maxAge != null && DateTime.now().difference(at) > maxAge) {
        return null;
      }
      return CachedValue(decoded['data'], at);
    } on Object {
      return null;
    }
  }

  static Future<void> remove(String box, String key) async {
    if (!_ready) return;
    await Hive.box<String>(box).delete(key);
  }

  /// Clears every cache box — called on logout so no tenant data survives a
  /// session switch.
  static Future<void> clearAll() async {
    if (!_ready) return;
    for (final name in _boxes) {
      await Hive.box<String>(name).clear();
    }
  }
}

class CachedValue {
  const CachedValue(this.data, this.writtenAt);

  final dynamic data;
  final DateTime writtenAt;
}
