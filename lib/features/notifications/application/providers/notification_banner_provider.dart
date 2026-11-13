import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/constants.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../domain/entities/app_notification.dart';
import 'notifications_providers.dart';

/// The notification the in-app banner is showing, or null.
///
/// One at a time: a newer arrival replaces the one on screen and restarts the
/// 15-second clock. Whoever shows it (a foreground push, or the unread poll
/// noticing a new row) goes through [show]; the banner itself only calls
/// [dismiss].
class IncomingNotificationController extends StateNotifier<AppNotification?> {
  IncomingNotificationController({Duration? duration})
      : _duration = duration ?? AppConstants.notificationBannerDuration,
        super(null);

  final Duration _duration;
  Timer? _timer;

  /// Ids shown this session — a push and the poll can both report the same
  /// row, and the second sighting must not bring the banner back.
  final _seen = <String>{};

  /// Whether [n] is new to this session. Recorded either way, so a row the
  /// caller then chooses not to show still counts as seen.
  bool markSeen(AppNotification n) => _seen.add(n.id);

  void show(AppNotification n) {
    _seen.add(n.id);
    _timer?.cancel();
    state = n;
    _timer = Timer(_duration, dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final incomingNotificationProvider =
    StateNotifierProvider<IncomingNotificationController, AppNotification?>(
        (ref) {
  // A new sign-in starts clean — nothing from the previous account lingers.
  ref.watch(sessionControllerProvider.select((s) => s.user?.id));
  return IncomingNotificationController();
});

/// Raises the banner for a notification that arrived while the app was in
/// the foreground, and refreshes the bell and the inbox so they agree with
/// it. Both the FCM foreground handler and the poll fallback end up here.
void announceNotification(ProviderContainer container, AppNotification n) {
  final ctrl = container.read(incomingNotificationProvider.notifier);
  if (!ctrl.markSeen(n)) return;
  ctrl.show(n);
  container.invalidate(notificationsUnreadCountProvider);
  container.read(notificationsProvider.notifier).refresh();
}

/// Fallback for a build without Firebase, and a safety net when a push is
/// dropped: when the once-a-minute unread count goes **up**, the newest
/// unread row is fetched and shown in the banner.
///
/// Only a rise counts — the first answer after sign-in is the baseline, and
/// a fall (something was read elsewhere) says nothing new. The latency is the
/// poll's: up to a minute, against a push's few seconds.
final newNotificationWatcherProvider = Provider<void>((ref) {
  int? last;
  ref.listen<AsyncValue<int?>>(notificationsUnreadCountProvider, (prev, next) {
    final count = next.valueOrNull;
    if (count == null) return;
    final before = last;
    last = count;
    if (before == null || count <= before) return;
    unawaited(_showNewestUnread(ref));
  });
});

Future<void> _showNewestUnread(Ref ref) async {
  try {
    final rows = await ref
        .read(notificationsRepositoryProvider)
        .getNotifications(status: 'unread');
    final ctrl = ref.read(incomingNotificationProvider.notifier);
    // The server lists newest first within the unread segment; the first row
    // not seen this session is the arrival that moved the count.
    for (final n in rows) {
      if (n.pinned || n.snoozed) continue;
      if (ctrl.markSeen(n)) {
        ctrl.show(n);
        ref.read(notificationsProvider.notifier).refresh();
        return;
      }
    }
  } on Object {
    // The bell still moved; the inbox has the row.
  }
}
