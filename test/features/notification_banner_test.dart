import 'package:clozrapp/core/services/push_notification_service.dart';
import 'package:clozrapp/features/notifications/application/providers/notification_banner_provider.dart';
import 'package:clozrapp/features/notifications/domain/entities/app_notification.dart';
import 'package:fake_async/fake_async.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    show RemoteNotification;
import 'package:flutter_test/flutter_test.dart';

AppNotification _n(String id, {String type = 'TaskAssigned'}) =>
    AppNotification(
      id: id,
      category: 'tasks',
      urgent: false,
      day: 'today',
      type: type,
      title: 'You have been assigned a task: "Call back"',
      body: 'Ashish',
      time: '1m',
      unread: true,
      targetKind: 'list',
      targetId: 'tasks',
    );

void main() {
  group('IncomingNotificationController', () {
    test('shows, then closes itself after the banner duration', () {
      fakeAsync((async) {
        final c =
            IncomingNotificationController(duration: const Duration(seconds: 15));
        c.show(_n('a'));
        expect(c.state?.id, 'a');
        async.elapse(const Duration(seconds: 14));
        expect(c.state?.id, 'a', reason: 'still up just before 15 s');
        async.elapse(const Duration(seconds: 1));
        expect(c.state, isNull, reason: 'gone at 15 s');
        c.dispose();
      });
    });

    test('a newer arrival replaces the one on screen and restarts the clock',
        () {
      fakeAsync((async) {
        final c =
            IncomingNotificationController(duration: const Duration(seconds: 15));
        c.show(_n('a'));
        async.elapse(const Duration(seconds: 10));
        c.show(_n('b'));
        async.elapse(const Duration(seconds: 10));
        expect(c.state?.id, 'b', reason: 'b has had only 10 s of its 15');
        async.elapse(const Duration(seconds: 5));
        expect(c.state, isNull);
        c.dispose();
      });
    });

    test('dismiss closes it at once and cancels the timer', () {
      fakeAsync((async) {
        final c = IncomingNotificationController();
        c.show(_n('a'));
        c.dismiss();
        expect(c.state, isNull);
        async.elapse(const Duration(seconds: 20));
        expect(c.state, isNull);
        c.dispose();
      });
    });

    test('markSeen is true once per id — push and poll cannot both show it',
        () {
      final c = IncomingNotificationController();
      expect(c.markSeen(_n('a')), isTrue);
      expect(c.markSeen(_n('a')), isFalse);
      c.show(_n('b'));
      expect(c.markSeen(_n('b')), isFalse, reason: 'show() records it too');
      c.dispose();
    });
  });

  group('notificationFromPush', () {
    test('builds the row the backend push describes', () {
      final n = notificationFromPush(
        {'notification_id': 'abc-123', 'type': 'TaskAssigned'},
        const RemoteNotification(
            title: 'New Task',
            body: 'You have been assigned a task: "Call back"'),
      );
      expect(n, isNotNull);
      expect(n!.id, 'abc-123');
      expect(n.type, 'TaskAssigned');
      // The notification text is what the inbox shows as the title.
      expect(n.title, 'You have been assigned a task: "Call back"');
      expect(n.unread, isTrue);
      expect(n.category, 'tasks');
      expect(n.targetKind, 'list');
      expect(n.targetId, 'tasks');
    });

    test('falls back to the title when the body is empty', () {
      final n = notificationFromPush(
          {'type': 'LeadAssigned'}, const RemoteNotification(title: 'New Lead'));
      expect(n?.title, 'New Lead');
      expect(n?.id, startsWith('push-'));
    });

    test('nothing to show → null', () {
      expect(notificationFromPush(const {}, null), isNull);
      expect(notificationFromPush(const {}, const RemoteNotification()), isNull);
    });
  });
}
