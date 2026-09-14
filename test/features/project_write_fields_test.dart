// The create and edit project forms collected thirteen fields and sent four
// (`project_name`, `priority`, `description`, `expected_end_date`). The
// manager, customer, type, status, team, assignees, cost, start date,
// visibility and progress method were gathered from the user and dropped —
// which is why a project's owner never came back after creating it.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/operations/application/project_write_fields.dart';

const _customers = [CatalogOption(id: 'cust-1', name: 'Kalyan Silks')];
const _types = [CatalogOption(id: 'type-1', name: 'Fit-out')];
const _statuses = [CatalogOption(id: 'stat-1', name: 'Planning')];
const _teams = [CatalogOption(id: 'team-1', name: 'Team North')];

Map<String, dynamic> build({
  String? customerLabel,
  String? typeLabel,
  String? statusLabel,
  String? teamLabel,
  String? managerId,
  Set<String> assigneeIds = const {},
  String? cost,
  DateTime? start,
  DateTime? end,
  String? visibility,
  String? progressMethod,
  String? percentComplete,
}) =>
    projectWriteFields(
      name: '  Showroom fit-out  ',
      priority: 'High',
      description: 'Ground floor',
      customerLabel: customerLabel,
      typeLabel: typeLabel,
      statusLabel: statusLabel,
      teamLabel: teamLabel,
      managerId: managerId,
      assigneeIds: assigneeIds,
      cost: cost,
      start: start,
      end: end,
      visibility: visibility,
      progressMethod: progressMethod,
      percentComplete: percentComplete,
      customers: _customers,
      types: _types,
      statuses: _statuses,
      teams: _teams,
    );

void main() {
  costParsingTests();
  group('the always-sent basics', () {
    test('name and description are trimmed', () {
      final body = build();
      expect(body['project_name'], 'Showroom fit-out');
      expect(body['priority'], 'High');
      expect(body['description'], 'Ground floor');
    });

    test('dates use the API form, not the display one', () {
      final body = build(start: DateTime(2026, 1, 5), end: DateTime(2026, 6, 28));
      expect(body['expected_start_date'], '2026-01-05');
      expect(body['expected_end_date'], '2026-06-28');
    });
  });

  group('FKs resolve to UUIDs, never labels', () {
    test('a picked label becomes its catalog id', () {
      final body = build(
        customerLabel: 'Kalyan Silks',
        typeLabel: 'Fit-out',
        statusLabel: 'Planning',
        teamLabel: 'Team North',
      );

      expect(body['customer'], 'cust-1');
      expect(body['project_type'], 'type-1');
      expect(body['status'], 'stat-1');
      expect(body['assigned_team'], 'team-1');
    });

    test('matching ignores case and surrounding space', () {
      expect(build(typeLabel: '  fit-out ')['project_type'], 'type-1');
    });

    test('a label the catalog does not know is omitted, not sent as a name', () {
      // Sending the label would be a 400: every FK is an org-scoped UUID.
      final body = build(typeLabel: 'Something Else', statusLabel: 'Nope');
      expect(body.containsKey('project_type'), isFalse);
      expect(body.containsKey('status'), isFalse);
    });

    test('an empty customer means internal — null, not omitted', () {
      // Omitting would leave an existing customer link untouched on a PATCH.
      final body = build(customerLabel: '');
      expect(body.containsKey('customer'), isTrue);
      expect(body['customer'], isNull);
    });

    test('an empty team clears the team the same way', () {
      final body = build(teamLabel: '');
      expect(body.containsKey('assigned_team'), isTrue);
      expect(body['assigned_team'], isNull);
    });
  });

  group('people', () {
    const uuid = '6dee7584-11b4-4851-88d4-4819c17bf0b0';

    setUp(() {
      UserDirectory.reset();
      UserDirectory.currentUserId = uuid;
    });

    test('the signed-in "me" sentinel is written as the real uuid', () {
      final body = build(managerId: 'me', assigneeIds: {'me'});
      expect(body['manager'], uuid);
      expect(body['assignees'], [uuid]);
    });

    test('a prototype id is dropped rather than posted', () {
      // `"assignees": ["dr"]` has been seen in the wild; the API rejects it.
      final body = build(managerId: 'dr', assigneeIds: {'dr', 'am'});
      expect(body.containsKey('manager'), isFalse);
      // Nothing resolved, so the key is omitted — sending `[]` would wipe the
      // project's real assignees over a mapping problem.
      expect(body.containsKey('assignees'), isFalse);
    });

    test('deselecting everyone clears the set, rather than saving no change', () {
      // Guarding on `isNotEmpty` meant removing the last assignee did nothing.
      final body = build(assigneeIds: const {});
      expect(body.containsKey('assignees'), isTrue);
      expect(body['assignees'], isEmpty);
    });

    test('a mixed set sends the ids that resolve', () {
      const other = 'd41ec856-7436-4b1d-8fa7-0c2b36476223';
      UserDirectory.register(userId: other, fullName: 'Manish Nair');

      final body = build(assigneeIds: {'me', other, 'dr'});
      expect(body['assignees'], containsAll([uuid, other]));
      expect(body['assignees'], isNot(contains('dr')));
    });
  });

  group('enums and money', () {
    test('visibility goes lowercase — "Organization" posts "organization"', () {
      expect(build(visibility: 'Organization')['visibility'], 'organization');
    });

    test('the progress method keeps its exact casing', () {
      // `percent_complete_method`, not `progress_method`.
      final body = build(progressMethod: 'Task Weight');
      expect(body['percent_complete_method'], 'Task Weight');
      expect(body.containsKey('progress_method'), isFalse);
    });

    test('a typed cost is stripped to a decimal string', () {
      expect(build(cost: '₹25,00,000')['estimated_costing'], '2500000');
    });

    test('an empty cost is omitted rather than sent as zero', () {
      expect(build(cost: '  ').containsKey('estimated_costing'), isFalse);
    });
  });

  // `percent_complete` was not sent at all, so the edit form's Progress box
  // accepted a number and discarded it.
  group('progress', () {
    test('a manual project sends its percent', () {
      final body = build(progressMethod: 'Manual', percentComplete: '40');
      expect(body['percent_complete'], '40');
    });

    test('any other method omits it — the API drops it silently there', () {
      // Task Completion / Progress / Weight all derive the figure from tasks.
      for (final method in ['Task Completion', 'Task Progress', 'Task Weight']) {
        final body = build(progressMethod: method, percentComplete: '40');
        expect(body.containsKey('percent_complete'), isFalse, reason: method);
      }
    });

    test('out-of-range values are clamped, junk is dropped', () {
      expect(build(progressMethod: 'Manual', percentComplete: '140')['percent_complete'], '100');
      expect(build(progressMethod: 'Manual', percentComplete: '-5')['percent_complete'], '0');
      expect(
        build(progressMethod: 'Manual', percentComplete: 'abc')
            .containsKey('percent_complete'),
        isFalse,
      );
    });

    test('an empty box is omitted, not sent as zero', () {
      expect(
        build(progressMethod: 'Manual', percentComplete: '')
            .containsKey('percent_complete'),
        isFalse,
      );
    });
  });
}

// The Estimated cost box's hint says "e.g. 18L", but the parser used to strip
// every non-digit and keep the rest — so "18L" was stored as ₹18 and "20K" as
// ₹20, silently. These pin the Indian short forms the hint invites, and that
// junk is refused rather than saved as a wrong number.
void costParsingTests() {
  group('cost short forms', () {
    test('K, L and Cr expand to rupees', () {
      expect(parseCostAmount('20K'), '20000');
      expect(parseCostAmount('18L'), '1800000');
      expect(parseCostAmount('1.5Cr'), '15000000');
      expect(parseCostAmount('2 lakh'), '200000');
    });

    test('plain and grouped numbers still pass through', () {
      expect(parseCostAmount('2500000'), '2500000');
      expect(parseCostAmount('₹25,00,000'), '2500000');
      expect(parseCostAmount('12.5'), '12.5');
    });

    test('case and spacing do not matter', () {
      expect(parseCostAmount('20k'), '20000');
      expect(parseCostAmount('18 L'), '1800000');
      expect(parseCostAmount(' 1.5 cr '), '15000000');
    });

    test('junk is refused, not stored as whatever digits were left', () {
      expect(parseCostAmount('twenty'), isNull);
      expect(parseCostAmount('20 dollars'), isNull);
      expect(parseCostAmount('20K5'), isNull);
      expect(isValidCostAmount('twenty'), isFalse);
    });

    test('empty is valid — the field is optional', () {
      expect(isValidCostAmount(''), isTrue);
      expect(isValidCostAmount('   '), isTrue);
    });
  });
}
