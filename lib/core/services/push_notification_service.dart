import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_router.dart';
import '../../features/auth/application/providers/auth_providers.dart';
import '../../features/notifications/application/notification_navigator.dart';
import '../../features/notifications/application/providers/notification_banner_provider.dart';
import '../../features/notifications/domain/entities/app_notification.dart';
import '../../features/notifications/infrastructure/data_sources/remote/notifications_remote_ds.dart';
import '../config/api_config.dart';
import '../config/firebase_options.dart';
import '../monitoring/app_monitoring.dart';
import '../network/api_endpoints.dart';
import '../network/network_providers.dart';
import 'push_device.dart';

/// Push notifications, end to end:
///
/// * **Permission** — asked once the user is signed in, through the OS dialog
///   (iOS, and Android 13+ `POST_NOTIFICATIONS`).
/// * **Device registration** — the FCM token goes to `POST /crm/devices/`
///   for the signed-in user, and `POST /crm/devices/refresh/` when Firebase
///   rotates it, so the backend's `send_push_notification` task reaches this
///   phone.
/// * **In the app** — a push that arrives while the app is open is *not* put
///   in the system tray; it becomes the in-app banner
///   ([incomingNotificationProvider]), which the user can tap, swipe away or
///   leave to close itself.
/// * **Out of the app** — the OS shows the push in the notification bar
///   (Firebase does that for a `notification` payload). Tapping it opens the
///   app and then the record the notification is about, through the same
///   [openNotification] the inbox uses.
///
/// Everything is best-effort: a build without Firebase values
/// ([DefaultFirebaseOptions.isConfigured]) skips all of this, and the unread
/// poll keeps the banner working.
class PushNotificationService {
  PushNotificationService._(this._container);

  final ProviderContainer _container;
  final _fcm = FirebaseMessaging.instance;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  ProviderSubscription<String?>? _sessionSub;

  String? _token;
  String? _registeredUser;

  /// A tap that arrived before the session was restored (cold start from the
  /// notification bar) — opened as soon as the user is signed in.
  RemoteMessage? _pendingOpen;

  static PushNotificationService? _instance;

  /// Wires push up for the running app. Safe to call when Firebase is not
  /// configured — it then does nothing and says so in the log.
  static Future<void> start(ProviderContainer container) async {
    if (_instance != null || !ApiConfig.apiEnabled) return;
    if (!DefaultFirebaseOptions.isConfigured) {
      debugPrint('Push: Firebase not configured '
          '(lib/core/config/firebase_options.dart) — push disabled, '
          'in-app banner runs off the unread poll.');
      return;
    }
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    } on Object catch (e, s) {
      unawaited(AppMonitoring.captureError(e, s,
          message: 'Firebase.initializeApp failed'));
      return;
    }
    final service = PushNotificationService._(container);
    _instance = service;
    await service._bind();
  }

  Future<void> _bind() async {
    // The app shows its own banner in the foreground, so iOS must not also
    // drop the system alert on top of it.
    await _fcm.setForegroundNotificationPresentationOptions(
        alert: false, badge: true, sound: false);

    _messageSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
    // App was closed and launched by a tap on the notification bar.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _onOpened(initial);

    _tokenSub = _fcm.onTokenRefresh.listen(_onTokenRefresh, onError: (_) {});

    // Follow the session: register on sign-in, forget on sign-out, and never
    // register a token against the previous account.
    _sessionSub = _container.listen<String?>(
      sessionControllerProvider.select((s) => s.user?.id),
      (_, userId) => unawaited(_onUser(userId)),
      fireImmediately: true,
    );
  }

  Future<void> _onUser(String? userId) async {
    if (userId == null) {
      _registeredUser = null;
      return;
    }
    if (_registeredUser == userId) return;
    _registeredUser = userId;
    await _requestPermissionAndRegister();
    final pending = _pendingOpen;
    if (pending != null) {
      _pendingOpen = null;
      await _openFromMessage(pending);
    }
  }

  /// The OS permission dialog, then the token. Asked after sign-in rather
  /// than at launch so the prompt lands on a user who knows what the app is.
  Future<void> _requestPermissionAndRegister() async {
    try {
      final settings =
          await _fcm.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push: notification permission denied');
        return;
      }
      final token = await _fcm.getToken();
      if (token == null || token.isEmpty) return;
      _token = token;
      _container.read(pushTokenProvider.notifier).state = token;
      await _register(token);
    } on Object catch (e, s) {
      unawaited(AppMonitoring.captureError(e, s,
          message: 'Push permission/registration failed'));
    }
  }

  static String get _platform => Platform.isIOS ? 'ios' : 'android';

  Future<void> _register(String token) async {
    final name =
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    await _container.read(apiServiceProvider).post(ApiEndpoints.devices, body: {
      'device_token': token,
      'platform': _platform,
      'device_name': name.length > 255 ? name.substring(0, 255) : name,
    });
  }

  Future<void> _onTokenRefresh(String token) async {
    final old = _token;
    _token = token;
    _container.read(pushTokenProvider.notifier).state = token;
    if (_registeredUser == null) return;
    try {
      if (old == null || old == token) {
        await _register(token);
      } else {
        await _container
            .read(apiServiceProvider)
            .post(ApiEndpoints.devicesRefresh, body: {
          'old_token': old,
          'new_token': token,
          'platform': _platform
        });
      }
    } on Object {
      // Re-registering is the fallback the server accepts for any token.
      try {
        await _register(token);
      } on Object catch (e, s) {
        unawaited(AppMonitoring.captureError(e, s,
            message: 'Push token refresh failed'));
      }
    }
  }

  /// A push while the app is open → the in-app banner.
  Future<void> _onForegroundMessage(RemoteMessage m) async {
    final n = await _toNotification(m);
    if (n == null) return;
    announceNotification(_container, n);
  }

  /// A tap on the notification bar while the app was in the background.
  void _onOpened(RemoteMessage m) {
    final signedIn = _container.read(sessionControllerProvider).isAuthenticated;
    if (!signedIn) {
      _pendingOpen = m;
      return;
    }
    unawaited(_openFromMessage(m));
  }

  Future<void> _openFromMessage(RemoteMessage m) async {
    final n = await _toNotification(m);
    if (n == null) return;
    _container.read(incomingNotificationProvider.notifier).markSeen(n);
    await openNotification(_container, appRouter, n);
  }

  /// The row the push is about: fetched by the `notification_id` the backend
  /// puts in the data payload, or rebuilt from the push itself (text + action
  /// keys) when the fetch fails (offline, deleted meanwhile) or there is no
  /// id (in-app notifications off).
  Future<AppNotification?> _toNotification(RemoteMessage m) async {
    final id = m.data['notification_id']?.toString() ?? '';
    final fetched = await fetchNotificationById(_container, id);
    final fromPush = notificationFromPush(m.data, m.notification);
    if (fetched == null) return fromPush;
    // The push and its row describe the same event; keep the push's target
    // if the row came back without one.
    if (fetched.action != null || fromPush?.action == null) return fetched;
    return AppNotification(
      id: fetched.id,
      category: fetched.category,
      urgent: fetched.urgent,
      day: fetched.day,
      type: fetched.type,
      title: fetched.title,
      body: fetched.body,
      time: fetched.time,
      unread: fetched.unread,
      targetKind: fetched.targetKind,
      targetId: fetched.targetId,
      pinned: fetched.pinned,
      snoozeUntil: fetched.snoozeUntil,
      action: fromPush!.action,
    );
  }

  /// Tears everything down (tests, and a future "sign out everywhere").
  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _messageSub?.cancel();
    await _openedSub?.cancel();
    _sessionSub?.close();
    _instance = null;
  }
}

/// Builds a row from the push itself — what the backend's
/// `send_push_notification` sends: data `{notification_id, type, resource,
/// id, api_url, context}` (all strings), a generic title ("New Task") and the
/// notification text as the body. Null when the push carries neither text
/// nor a tap target.
///
/// `notification_id` is missing when the user turned in-app notifications
/// off but kept push: the row then gets a synthetic id
/// ([AppNotification.syntheticIdPrefix]) and is never marked read.
AppNotification? notificationFromPush(
    Map<String, dynamic> data, RemoteNotification? notification) {
  final text = (notification?.body ?? '').trim();
  final title = (notification?.title ?? '').trim();
  final action = NotificationAction.fromPushData(data);
  if (text.isEmpty && title.isEmpty && action == null) return null;
  final id = data['notification_id']?.toString() ?? '';
  final row = notificationFromJson({
    'crm_notification_id': id.isEmpty
        ? '${AppNotification.syntheticIdPrefix}'
            '${DateTime.now().microsecondsSinceEpoch}'
        : id,
    'type': data['type']?.toString() ?? '',
    'notification_text': text.isEmpty ? title : text,
    'read': false,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });
  if (row == null || action == null) return row;
  return AppNotification(
    id: row.id,
    category: row.category,
    urgent: row.urgent,
    day: row.day,
    type: row.type,
    title: row.title,
    body: row.body,
    time: row.time,
    unread: row.unread,
    targetKind: row.targetKind,
    targetId: row.targetId,
    action: action,
  );
}
