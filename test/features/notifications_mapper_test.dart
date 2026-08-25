import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/notifications/domain/entities/app_notification.dart';
import 'package:clozrapp/features/notifications/infrastructure/data_sources/remote/notifications_remote_ds.dart';

void main() {
  final now = DateTime(2026, 8, 4, 10, 0);

  group('notificationFromJson', () {
    test('maps a full CRM row (uuid id, category, icon combo, html body)', () {
      final n = notificationFromJson(<String, dynamic>{
        'crm_notification_id': '0f6c1d2e-aaaa-bbbb-cccc-1234567890ab',
        'type': 'LeadAssigned',
        'category': 'crm',
        'notification_text': 'New lead assigned to you',
        'message': '<p>Anjana routed <b>Malabar Gold</b> into your pipeline.</p>',
        'read': false,
        'status': 'unread',
        'created_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
      }, now: now)!;

      expect(n.id, '0f6c1d2e-aaaa-bbbb-cccc-1234567890ab');
      expect(n.category, 'leads'); // crm → leads
      expect(n.urgent, false);
      expect(n.day, 'today');
      expect(n.time, '2h ago');
      expect(n.title, 'New lead assigned to you');
      expect(n.body, 'Anjana routed Malabar Gold into your pipeline.');
      expect(n.unread, true);
      // The icon trio is resolved by the row widget now (notificationLook);
      // the mapper's job is the category/urgency that decide it.
      expect(n.icon, isNull);
      expect(n.type, 'LeadAssigned');
      // A lead event now opens the Leads list — see the target test below.
      expect(n.targetKind, 'list');
      expect(n.targetId, 'leads');
      expect(n.hasTarget, true);
    });

    test('server categories map onto the UI keys', () {
      AppNotification make(String type, String category) =>
          notificationFromJson(<String, dynamic>{
            'crm_notification_id': 'x',
            'type': type,
            'category': category,
          }, now: now)!;

      expect(make('ProjectUpdateFiled', 'pmo').category, 'ops');
      expect(make('LMSCourseAssigned', 'lms').category, 'training');
      expect(make('PaymentFailed', 'billing').category, 'payments');
      expect(make('SystemUpdate', 'system').category, 'system');
      // Type refinements win over the module category.
      expect(make('TaskAssigned', 'crm').category, 'tasks');
      expect(make('FollowUpDueReminder', 'crm').category, 'tasks');
      expect(make('TicketEscalated', 'crm').category, 'help');
      expect(make('IssueReplyAdded', 'crm').category, 'help');
      // Unknown category → system.
      expect(make('Whatever', '').category, 'system');
    });

    test('list-level targets derive from the type', () {
      AppNotification make(String type, String category) =>
          notificationFromJson(<String, dynamic>{
            'crm_notification_id': 'x',
            'type': type,
            'category': category,
          }, now: now)!;

      final lms = make('LMSCourseAssigned', 'lms');
      expect(lms.targetKind, 'list');
      expect(lms.targetId, 'lmsMy');

      final billing = make('PaymentFailed', 'billing');
      expect(billing.targetKind, 'list');
      expect(billing.targetId, 'billing');

      // No source-object id in the row — not even on the detail endpoint — so
      // a record link is impossible; the module list is the honest target.
      final lead = make('LeadAssigned', 'crm');
      expect(lead.targetKind, 'list');
      expect(lead.targetId, 'leads');

      // PMO task events are `PmoTask*`, which must not fall into `task*`.
      expect(make('PmoTaskAssigned', 'pmo').targetId, 'opsTasks');
      expect(make('TaskAssigned', 'crm').targetId, 'tasks');
      expect(make('ProjectAssigned', 'pmo').targetId, 'projects');
      expect(make('FollowUpDueReminder', 'crm').targetId, 'followups');
      expect(make('UserAdded', 'system').targetId, 'members');

      // A type in no known module still has nowhere to go.
      expect(make('SomethingElse', 'system').targetKind, 'none');
    });

    test('INT pk rows stringify when the uuid field is absent', () {
      final n = notificationFromJson(<String, dynamic>{
        'id': 123,
        'type': 'SystemUpdate',
        'category': 'system',
      }, now: now)!;
      expect(n.id, '123');
    });

    test('unread mapping — read/is_read flags with status fallback', () {
      AppNotification make(Map<String, dynamic> extra) =>
          notificationFromJson(<String, dynamic>{
            'crm_notification_id': 'x',
            'type': 'SystemUpdate',
            'category': 'system',
            ...extra,
          }, now: now)!;

      expect(make({'read': true}).unread, false);
      expect(make({'read': false}).unread, true);
      expect(make({'is_read': false}).unread, true); // defensive alias
      expect(make({'status': 'unread'}).unread, true);
      expect(make({'status': 'read'}).unread, false);
      expect(make({}).unread, false); // no signal → no phantom badge
    });

    // The serializer sends no urgency field at all, so before this the design's
    // red/amber treatment never appeared on a live row.
    test('urgency comes from the event type', () {
      bool urgent(String type) => notificationFromJson(<String, dynamic>{
            'crm_notification_id': 'x',
            'type': type,
            'category': 'pmo',
          }, now: now)!
              .urgent;

      expect(urgent('PmoTaskDueReminder'), isTrue);
      expect(urgent('ProjectDeadlineApproaching'), isTrue);
      expect(urgent('LMSDeadlineMissed'), isTrue);
      expect(urgent('PaymentOverdue'), isTrue);
      expect(urgent('SlaBreached'), isTrue);

      // Routine events stay routine.
      expect(urgent('PmoTaskAssigned'), isFalse);
      expect(urgent('ProjectCommentAdded'), isFalse);
      expect(urgent('UserAdded'), isFalse);
    });

    // `message` is empty on every live row, so the row's second line was blank.
    test('the actor fills the body when there is no message', () {
      final n = notificationFromJson(<String, dynamic>{
        'crm_notification_id': 'x',
        'type': 'PmoTaskAssigned',
        'category': 'pmo',
        'notification_text': 'You have been assigned a task: Write unit tests',
        'message': '',
        'from_user_name': 'Kavita Das',
      }, now: now)!;

      expect(n.title, 'You have been assigned a task: Write unit tests');
      expect(n.body, 'Kavita Das');
    });

    test('a real message still wins over the actor', () {
      final n = notificationFromJson(<String, dynamic>{
        'crm_notification_id': 'x',
        'type': 'LeadNoteAdded',
        'category': 'crm',
        'notification_text': 'New note added',
        'message': '<p>Competitor comparison notes</p>',
        'from_user_name': 'Priya Saxena',
      }, now: now)!;

      expect(n.body, 'Competitor comparison notes');
    });

    test('urgent flag is defensive (no server field today)', () {
      final n = notificationFromJson(<String, dynamic>{
        'crm_notification_id': 'x',
        'type': 'PaymentFailed',
        'category': 'billing',
        'priority': 'high',
      }, now: now)!;
      expect(n.urgent, true);
    });

    test('defensive nulls — empty rows skip, sparse rows fall back', () {
      expect(notificationFromJson(<String, dynamic>{}, now: now), isNull);

      final sparse = notificationFromJson(
          <String, dynamic>{'crm_notification_id': 'y'}, now: now)!;
      expect(sparse.category, 'system');
      expect(sparse.title, 'Notification');
      expect(sparse.body, '');
      expect(sparse.day, 'earlier'); // no created_at
      expect(sparse.time, '');
      expect(sparse.targetKind, 'none');

      final typed = notificationFromJson(<String, dynamic>{
        'crm_notification_id': 'z',
        'type': 'QuotationExpiryReminder',
        'category': 'crm',
      }, now: now)!;
      expect(typed.title, 'Quotation expiry reminder'); // humanized type
    });
  });

  group('notificationDayBucket', () {
    test('buckets on calendar days against the injected now', () {
      expect(
        notificationDayBucket(DateTime(2026, 8, 4, 0, 30), now: now),
        'today',
      );
      expect(
        notificationDayBucket(DateTime(2026, 8, 3, 23, 59), now: now),
        'yesterday',
      );
      expect(
        notificationDayBucket(DateTime(2026, 8, 2, 12, 0), now: now),
        'earlier',
      );
      expect(notificationDayBucket(null, now: now), 'earlier');
    });
  });
}
