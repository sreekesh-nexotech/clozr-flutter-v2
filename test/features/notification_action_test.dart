import 'package:clozrapp/app/router/routes.dart';
import 'package:clozrapp/core/services/push_notification_service.dart';
import 'package:clozrapp/features/notifications/application/notification_navigator.dart';
import 'package:clozrapp/features/notifications/domain/entities/app_notification.dart';
import 'package:clozrapp/features/notifications/infrastructure/data_sources/remote/notifications_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

/// notification-tap-action-integration.md: every row / push carries an
/// `action` naming the record a tap opens.
void main() {
  const taskId = '8d0c2f1e-5b7a-4c1d-9e3f-0a1b2c3d4e5f';

  String? route(String resource, {String? id, Map<String, dynamic>? ctx}) =>
      routeForNotificationAction(NotificationAction(
          resource: resource, id: id, context: ctx ?? const {}));

  group('inbox row action', () {
    test('parses a record action', () {
      final n = notificationFromJson({
        'crm_notification_id': 'n1',
        'type': 'NoteMention',
        'category': 'crm',
        'notification_text': 'Jane Smith mentioned you in a note',
        'action': {
          'resource': 'crm_task',
          'id': taskId,
          'api_url': '/api/v1/crm/tasks/$taskId/',
          'context': {'note_id': 'note-1', 'is_followup': false},
        },
      })!;
      expect(n.action!.resource, 'crm_task');
      expect(n.action!.id, taskId);
      expect(n.action!.context['note_id'], 'note-1');
      expect(n.action!.isFollowup, false);
      expect(n.hasTarget, true);
    });

    test('a page action has no id', () {
      final n = notificationFromJson({
        'crm_notification_id': 'n2',
        'type': 'PaymentFailed',
        'category': 'billing',
        'action': {
          'resource': 'billing',
          'id': null,
          'api_url': null,
          'context': {},
        },
      })!;
      expect(n.action!.resource, 'billing');
      expect(n.action!.id, isNull);
      expect(n.hasTarget, true);
    });

    test('action: null keeps the text-derived fallback target', () {
      final n = notificationFromJson({
        'crm_notification_id': 'n3',
        'type': 'LeadAssigned',
        'category': 'crm',
        'action': null,
      })!;
      expect(n.action, isNull);
      expect(n.targetKind, 'list');
      expect(n.targetId, 'leads');
      expect(n.hasTarget, true);
    });

    test('a resource with no mobile screen is not openable', () {
      for (final r in ['call_log', 'account_security', 'org_backup', 'zzz']) {
        final n = notificationFromJson({
          'crm_notification_id': 'n4',
          'type': 'LeadAssigned', // would otherwise fall back to Leads
          'action': {'resource': r, 'id': null, 'context': {}},
        })!;
        expect(n.hasTarget, false, reason: r);
      }
    });

    test('copyWith keeps the action', () {
      final n = notificationFromJson({
        'crm_notification_id': 'n5',
        'action': {'resource': 'lead', 'id': 'L1', 'context': {}},
      })!;
      expect(n.copyWith(unread: false).action!.id, 'L1');
    });
  });

  group('resource → route', () {
    test('record resources open their detail screen by id', () {
      expect(route('lead', id: 'a'), '${Routes.leadDetail}?id=a');
      expect(route('customer', id: 'a'), '${Routes.customerDetail}?id=a');
      expect(route('crm_task', id: 'a'), '${Routes.taskDetail}?id=a');
      expect(route('crm_task', id: 'a', ctx: {'is_followup': true}),
          '${Routes.followupDetail}?id=a');
      expect(route('issue', id: 'a'), '${Routes.ticketDetail}?id=a');
      expect(route('project', id: 'a'), '${Routes.projectDetail}?id=a');
      expect(route('project_task', id: 'a'), '${Routes.opsTaskDetail}?id=a');
      expect(route('quotation', id: 'a'), '${Routes.quoteDetail}?id=a');
      expect(route('lms_enrollment', id: 'a'),
          '${Routes.lmsPlayer}?enrollment=a');
      expect(route('lms_course', id: 'a'), '${Routes.lmsCourseDetail}?id=a');
      expect(route('approval', id: 'a'), '${Routes.approvalDetail}?id=a');
      expect(route('user', id: 'a'), '${Routes.memberDetail}?id=a');
    });

    test('page actions open the page', () {
      expect(route('billing'), Routes.billing);
      expect(route('goals_rewards'), Routes.rewards);
    });

    test('no screen → null (mark read, stay put)', () {
      expect(route('call_log', id: 'a'), isNull);
      expect(route('account_security'), isNull);
      expect(route('org_backup'), isNull);
      expect(route('something_new', id: 'a'), isNull);
      // A record resource without its id cannot be opened.
      expect(route('lead'), isNull);
    });

    test('every openable resource has a route', () {
      for (final r in NotificationAction.openableResources) {
        expect(route(r, id: r == 'billing' || r == 'goals_rewards' ? null : 'x'),
            isNotNull,
            reason: r);
      }
    });
  });

  group('push payload', () {
    test('string values, JSON-encoded context', () {
      final n = notificationFromPush({
        'notification_id': 'n1',
        'type': 'NoteMention',
        'resource': 'crm_task',
        'id': taskId,
        'api_url': '/api/v1/crm/tasks/$taskId/',
        'context': '{"note_id": "note-1", "is_followup": true}',
      }, null)!;
      expect(n.id, 'n1');
      expect(n.hasInboxRow, true);
      expect(n.action!.resource, 'crm_task');
      expect(n.action!.id, taskId);
      expect(n.action!.isFollowup, true);
      expect(route('crm_task', id: taskId, ctx: n.action!.context),
          '${Routes.followupDetail}?id=$taskId');
    });

    test('page action: id is ""', () {
      final a = NotificationAction.fromPushData({
        'resource': 'billing',
        'id': '',
        'api_url': '',
        'context': '{}',
      })!;
      expect(a.id, isNull);
      expect(routeForNotificationAction(a), Routes.billing);
    });

    test('no action keys → no action', () {
      expect(NotificationAction.fromPushData({'type': 'LeadAssigned'}),
          isNull);
    });

    test('bad context string still keeps the record', () {
      final a = NotificationAction.fromPushData(
          {'resource': 'lead', 'id': 'L1', 'context': 'not json'})!;
      expect(a.id, 'L1');
      expect(a.context, isEmpty);
    });

    test('no notification_id → synthetic row that is never marked read', () {
      final n = notificationFromPush({
        'type': 'NoteMention',
        'resource': 'lead',
        'id': 'L1',
        'context': '{}',
      }, null)!;
      expect(n.hasInboxRow, false);
      expect(n.id, startsWith(AppNotification.syntheticIdPrefix));
      expect(n.action!.id, 'L1');
    });
  });
}
