import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/operations/application/ops_task_write_fields.dart';

void main() {
  setUp(UserDirectory.reset);
  tearDown(UserDirectory.reset);

  const statuses = [
    CatalogOption(id: 'st-open', name: 'Open'),
    CatalogOption(id: 'st-working', name: 'Working'),
  ];

  Map<String, dynamic> build({
    String subject = 'Snag list & handover',
    String? projectId = 'proj-1',
    String? groupId,
    String? statusLabel,
    Set<String> assigneeIds = const {},
    DateTime? start,
    TimeOfDay? startTime,
    DateTime? end,
    TimeOfDay? endTime,
  }) =>
      opsTaskWriteFields(
        subject: subject,
        priority: 'High',
        description: 'Walk the site.',
        projectId: projectId,
        groupId: groupId,
        statusLabel: statusLabel,
        assigneeIds: assigneeIds,
        start: start,
        startTime: startTime,
        end: end,
        endTime: endTime,
        statuses: statuses,
      );

  const meUuid = 'acaec99f-9001-48b0-ad30-0f2c4ae06240';
  const mateUuid = 'f126141c-1002-4c33-9a11-0f2c4ae06241';

  test('carries every field the form collects, under the documented keys', () {
    UserDirectory.currentUserId = meUuid;
    UserDirectory.registerJson(const {'user_id': mateUuid, 'first_name': 'Asha'});
    final f = build(
      groupId: 'grp-1',
      statusLabel: 'Working',
      assigneeIds: {'me', mateUuid},
      start: DateTime(2026, 6, 28),
      startTime: const TimeOfDay(hour: 9, minute: 0),
      end: DateTime(2026, 6, 30),
      endTime: const TimeOfDay(hour: 17, minute: 30),
    );

    // `subject`, not `title` — the column header lies about the field name.
    expect(f['subject'], 'Snag list & handover');
    expect(f['project'], 'proj-1');
    expect(f['task_group'], 'grp-1');
    expect(f['status'], 'st-working');
    expect(f['priority'], 'High');
    expect(f['description'], 'Walk the site.');
    expect(f['assignees'], [meUuid, mateUuid]);
    // Asserted as instants, not as strings: the wire value is UTC, so its
    // digits depend on the machine's zone. What must hold everywhere is that
    // it round-trips back to the wall-clock time the user picked.
    expect(DateTime.parse(f['exp_start_date'] as String).toLocal(),
        DateTime(2026, 6, 28, 9, 0));
    expect(DateTime.parse(f['exp_end_date'] as String).toLocal(),
        DateTime(2026, 6, 30, 17, 30));
  });

  test('the status label resolves case-insensitively to the org id', () {
    // The built-in default is the folded key 'open'; the org calls it "Open".
    expect(build(statusLabel: 'open')['status'], 'st-open');
  });

  test('an unmatched status is omitted, so the server applies its default', () {
    // Better than guessing: an org that renamed its lanes has no "Open", and a
    // bad uuid would 400 where an absent key just takes the default status.
    expect(build(statusLabel: 'Backlog').containsKey('status'), isFalse);
    expect(build(statusLabel: '').containsKey('status'), isFalse);
    expect(build().containsKey('status'), isFalse);
  });

  test('"No group" sends no task_group at all', () {
    expect(build(groupId: '').containsKey('task_group'), isFalse);
    expect(build().containsKey('task_group'), isFalse);
  });

  test('a date with no time lands at local midnight, and no date sends no key', () {
    expect(DateTime.parse(build(end: DateTime(2026, 6, 30))['exp_end_date'] as String).toLocal(),
        DateTime(2026, 6, 30));
    expect(build().containsKey('exp_start_date'), isFalse);
    expect(build().containsKey('exp_end_date'), isFalse);
  });

  test('stamps go out as an explicit UTC instant, never unlabelled digits', () {
    // Unlabelled, the server guesses the zone: 5 PM IST was being stored as
    // 5 PM UTC and read back as 10:30 PM. The Z is what makes it unambiguous.
    final f = build(end: DateTime(2026, 6, 30), endTime: const TimeOfDay(hour: 17, minute: 0));
    final wire = f['exp_end_date'] as String;

    expect(wire, endsWith('Z'));
    expect(DateTime.parse(wire).isUtc, isTrue);
    expect(DateTime.parse(wire).toLocal(), DateTime(2026, 6, 30, 17, 0));
  });

  test("'me' needs a signed-in user; prototype ids are never posted", () {
    // No current user: 'me' cannot resolve, and the rest of the selection is
    // empty, so the key is dropped rather than posting a partial set.
    expect(build(assigneeIds: {'me'}).containsKey('assignees'), isFalse);
    // A prototype seed id ('dr') is not a UUID and must not reach the API.
    expect(build(assigneeIds: {'dr'}).containsKey('assignees'), isFalse);
  });

  test('no assignees picked still sends the empty set', () {
    expect(build()['assignees'], isEmpty);
  });

  test('a standalone task sends no project', () {
    expect(build(projectId: null).containsKey('project'), isFalse);
    expect(build(projectId: '').containsKey('project'), isFalse);
  });

  test('subject and description are trimmed', () {
    final f = opsTaskWriteFields(
      subject: '  Fix the thing  ',
      priority: 'Low',
      description: '  detail  ',
    );
    expect(f['subject'], 'Fix the thing');
    expect(f['description'], 'detail');
  });
}
