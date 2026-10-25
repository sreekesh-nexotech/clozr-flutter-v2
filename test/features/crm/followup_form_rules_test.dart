import 'package:clozrapp/features/crm/application/followup_form_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 24);

  group('due date', () {
    test('bounds: 01-Jan-2000 … today + 5 years', () {
      expect(followupDueDateError(null, today: today), isNull);
      expect(followupDueDateError(DateTime(2026, 10, 1), today: today), isNull);
      expect(followupDueDateError(DateTime(1999, 12, 31), today: today), "The due date can't be before 01-Jan-2000.");
      expect(followupDueDateError(DateTime(2031, 10, 24), today: today), isNull);
      expect(followupDueDateError(DateTime(2031, 10, 25), today: today),
          "The due date can't be more than 5 years ahead (latest 24-Oct-2031).");
    });

    test('past dates are overdue, today is not', () {
      expect(isPastDueDate(DateTime(2026, 10, 23), today: today), isTrue);
      expect(isPastDueDate(DateTime(2026, 10, 24, 0, 1), today: today), isFalse);
      expect(isPastDueDate(null, today: today), isFalse);
    });
  });

  test('meeting types and window', () {
    expect(isMeetingType('Site Meeting'), isTrue);
    expect(isMeetingType('Call'), isFalse);
    final a = DateTime(2026, 10, 24, 10);
    expect(meetingWindowError(a, a), isNull);
    expect(meetingWindowError(a, a.subtract(const Duration(minutes: 1))), meetingOrderMessage);
    expect(meetingWindowError(null, a), isNull);
  });

  group('custom fields', () {
    test('parses the wire list: inactive dropped, unknown type → text, missing applies_to → all, ordered', () {
      final defs = TaskCustomFieldDef.listFromResponse({
        'results': [
          {'custom_field_id': '2', 'field_name': 'b', 'label': 'B', 'field_type': 'weird', 'order': 2},
          {'custom_field_id': '1', 'field_name': 'a', 'label': 'A', 'field_type': 'dropdown', 'order': 1,
            'choices': ['x', {'value': 'y'}, 'x'], 'applies_to': 'followup', 'is_required': true},
          {'custom_field_id': '3', 'field_name': 'c', 'is_active': false},
        ],
      });
      expect(defs.map((d) => d.name), ['a', 'b']);
      expect(defs.first.choices, ['x', 'y']);
      expect(defs.first.required, isTrue);
      expect(defs.first.appliesTo, 'followup');
      expect(defs.last.type, 'text');
      expect(defs.last.appliesTo, 'all');
    });

    test('a follow-up keeps all + followup fields, not task ones', () {
      const defs = [
        TaskCustomFieldDef(id: '1', name: 't', label: 'T', type: 'text', appliesTo: 'task', order: 1),
        TaskCustomFieldDef(id: '2', name: 'f', label: 'F', type: 'text', appliesTo: 'followup', order: 3),
        TaskCustomFieldDef(id: '3', name: 'x', label: 'X', type: 'text', order: 2),
      ];
      expect(customFieldsForKind(defs, isFollowup: true).map((d) => d.name), ['x', 'f']);
      expect(customFieldsForKind(defs, isFollowup: false).map((d) => d.name), ['t', 'x']);
    });

    test('collect: shapes values, reports errors with the webapp messages', () {
      const defs = [
        TaskCustomFieldDef(id: '1', name: 'req', label: 'Req', type: 'text', required: true),
        TaskCustomFieldDef(id: '2', name: 'n', label: 'N', type: 'decimal'),
        TaskCustomFieldDef(id: '3', name: 'b', label: 'B', type: 'boolean'),
        TaskCustomFieldDef(id: '4', name: 'm', label: 'M', type: 'multi_select', choices: ['p', 'q']),
        TaskCustomFieldDef(id: '5', name: 'e', label: 'E', type: 'email'),
        TaskCustomFieldDef(id: '6', name: 'u', label: 'U', type: 'url'),
        TaskCustomFieldDef(id: '7', name: 'd', label: 'D', type: 'date'),
        TaskCustomFieldDef(id: '8', name: 'opt', label: 'Opt', type: 'text'),
        TaskCustomFieldDef(id: '9', name: 'dd', label: 'DD', type: 'dropdown', choices: ['one']),
      ];
      final r = collectCustomFields(defs, {
        'req': '  ',
        'n': '12.5',
        'm': ['q', 'zzz'],
        'e': 'nope',
        'u': 'example.com',
        'd': '2026-02-31',
        'dd': 'two',
      });
      expect(r.values, {'n': 12.5, 'b': false, 'm': ['q']});
      expect(r.errors, {
        'req': 'This field is required.',
        'e': 'Must be a valid email address.',
        'u': 'Must be a valid URL (http:// or https://).',
        'd': 'Must be a date (YYYY-MM-DD).',
        'dd': 'Pick one of the options.',
      });
      expect(collectCustomFields(const [TaskCustomFieldDef(id: '1', name: 'n', label: 'N', type: 'number')], {'n': 'abc'}).errors,
          {'n': 'Must be a numeric value.'});
    });
  });

  group('form', () {
    test('can save needs a title and a type', () {
      expect(followupCanSave(const FollowupDraft(title: ' ', type: 'Call')), isFalse);
      expect(followupCanSave(const FollowupDraft(title: 'x')), isFalse);
      expect(followupCanSave(const FollowupDraft(title: 'x', type: 'Call')), isTrue);
    });

    test('errors: reminder without a date, meeting order, custom fields', () {
      final d = FollowupDraft(
        title: 'x',
        type: 'Call',
        reminder: '1hour',
        meetingFrom: DateTime(2026, 10, 24, 10),
        meetingTo: DateTime(2026, 10, 24, 9),
      );
      const defs = [TaskCustomFieldDef(id: '1', name: 'r', label: 'R', type: 'text', required: true)];
      expect(followupFormErrors(d, defs, const {}, today: today), {
        'reminder': 'A due date is required when setting a reminder.',
        'meetingTo': 'Meeting end cannot be before the meeting start.',
        'custom_fields.r': 'This field is required.',
      });
      expect(followupFormErrors(const FollowupDraft(title: 'x', type: 'Call'), const [], const {}, today: today), isEmpty);
    });

    test('body: minimal create leaves the optionals out', () {
      expect(buildFollowupCreateBody(const FollowupDraft(title: '  Ring back ', type: 'Call', dueTime: '10:00', reminder: '1hour'), const {}), {
        'title': 'Ring back',
        'task_type': 'Call',
        'is_followup': true,
      });
    });

    test('body: everything, as the webapp sends it', () {
      final from = DateTime.utc(2026, 10, 25, 4, 30);
      final body = buildFollowupCreateBody(
        FollowupDraft(
          title: 'Follow up on quote',
          type: 'Meeting',
          statusId: 's1',
          priorityId: 'p1',
          assignedTo: 'u1',
          extraAssignees: const ['u2'],
          teamId: 't1',
          dueDate: DateTime(2026, 10, 25),
          dueTime: '09:30',
          reminder: '1hour',
          meetingFrom: from,
          meetingTo: from.add(const Duration(hours: 1)),
          location: ' Zoom ',
          description: ' About the quote ',
          relatedTo: 'customer',
          relatedToId: 'c1',
        ),
        const {'budget': 10},
      );
      expect(body, {
        'title': 'Follow up on quote',
        'task_type': 'Meeting',
        'is_followup': true,
        'due_date': '2026-10-25',
        'due_time': '09:30',
        'description': 'About the quote',
        'assigned_to': 'u1',
        'assignees': ['u1', 'u2'],
        'assigned_team': 't1',
        'status_id': 's1',
        'priority': 'p1',
        'related_to': 'customer',
        'related_to_id': 'c1',
        'reminder_choice': '1hour',
        'meeting_from': '2026-10-25T04:30:00.000Z',
        'meeting_to': '2026-10-25T05:30:00.000Z',
        'location': 'Zoom',
        'custom_fields': {'budget': 10},
      });
    });

    test('body: a lone assignee set is not sent as assignees (webapp)', () {
      final only = buildFollowupCreateBody(const FollowupDraft(title: 'x', type: 'Call', assignedTo: 'u1'), const {});
      expect(only['assigned_to'], 'u1');
      expect(only.containsKey('assignees'), isFalse);
      final unknownReminder =
          buildFollowupCreateBody(FollowupDraft(title: 'x', type: 'Call', dueDate: DateTime(2026, 1, 1), reminder: 'bogus'), const {});
      expect(unknownReminder.containsKey('reminder_choice'), isFalse);
    });
  });
}
