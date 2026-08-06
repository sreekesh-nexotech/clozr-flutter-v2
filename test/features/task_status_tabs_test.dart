import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/providers/crm_catalog_providers.dart';
import 'package:clozrapp/features/crm/application/providers/crm_tasks_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_task.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/crm_tasks_remote_ds.dart';

/// The Tasks screen used to hard-code its status tabs as the four folded
/// buckets — To do / In Progress / Blocked / Done — so an org whose lanes are
/// Open / In Progress / Completed / Cancelled saw names it does not use.
/// These pin the org's own vocabulary reaching the tabs and the card pill.
void main() {
  /// The seed org's real lanes, as `/crm/crm-task-statuses/` returns them.
  const orgLanes = [
    CatalogOption(id: 's-open', name: 'Open', statusType: 'open'),
    CatalogOption(id: 's-prog', name: 'In Progress', statusType: 'in_progress'),
    CatalogOption(id: 's-done', name: 'Completed', statusType: 'completed'),
    CatalogOption(id: 's-cancel', name: 'Cancelled', statusType: 'cancelled'),
  ];

  CrmTask task({String status = 'todo', String statusName = ''}) => CrmTask(
        id: 'T1',
        title: 'Prepare BOQ',
        type: 'Task',
        leadId: null,
        status: status,
        statusName: statusName,
        priority: 'Medium',
        assignee: 'me',
        due: '16 Jun 2026',
        dueNote: '',
      );

  group('the mapper keeps the org lane name', () {
    test('statusName is the API value, status is the folded bucket', () {
      final mapped = CrmTasksRemoteDataSource.taskFromJson({
        'task_id': 'T1',
        'title': 'Prepare BOQ',
        'status': 'Cancelled',
      })!;

      expect(mapped.statusName, 'Cancelled');
      // Folded for colour and done-ness — which is exactly why the raw name
      // has to survive alongside it.
      expect(mapped.status, 'blocked');
    });

    test('a nested status object is read the same way', () {
      final mapped = CrmTasksRemoteDataSource.taskFromJson({
        'task_id': 'T1',
        'status': {'name': 'Open'},
      })!;

      expect(mapped.statusName, 'Open');
      expect(mapped.status, 'todo');
    });

    test('a row with no status leaves the name empty, not "null"', () {
      final mapped = CrmTasksRemoteDataSource.taskFromJson({'task_id': 'T1'})!;
      expect(mapped.statusName, '');
    });
  });

  group('crmTaskInTab', () {
    test('matches the org lane name, case-insensitively', () {
      final t = task(status: 'todo', statusName: 'Open');
      expect(crmTaskInTab(t, 'Open'), isTrue);
      expect(crmTaskInTab(t, 'open'), isTrue);
      expect(crmTaskInTab(t, 'Completed'), isFalse);
    });

    test('still matches a built-in key, so the pre-catalog tabs work', () {
      // The catalog is fetched at mount; until it lands the tabs are the
      // built-in four and must keep filtering.
      expect(crmTaskInTab(task(status: 'todo', statusName: 'Open'), 'todo'), isTrue);
      expect(crmTaskInTab(task(status: 'done', statusName: 'Completed'), 'done'), isTrue);
    });

    test('a mock row with no lane name falls back to its folded key', () {
      expect(crmTaskInTab(task(status: 'blocked'), 'blocked'), isTrue);
      expect(crmTaskInTab(task(status: 'blocked'), 'Cancelled'), isFalse);
    });

    test('two lanes that fold to the same bucket stay distinct', () {
      // "Cancelled" and a hypothetical "Blocked" both fold to `blocked`; the
      // tabs must not merge them.
      final cancelled = task(status: 'blocked', statusName: 'Cancelled');
      expect(crmTaskInTab(cancelled, 'Cancelled'), isTrue);
      expect(crmTaskInTab(cancelled, 'On hold'), isFalse);
    });
  });

  group('crmTaskTabCount', () {
    final tasks = [
      task(status: 'todo', statusName: 'Open'),
      task(status: 'todo', statusName: 'Open'),
      task(status: 'done', statusName: 'Completed'),
    ];

    test('counts by the org lane name', () {
      expect(crmTaskTabCount(tasks, 'Open'), 2);
      expect(crmTaskTabCount(tasks, 'Completed'), 1);
      expect(crmTaskTabCount(tasks, 'Cancelled'), 0);
    });

    test('all counts everything', () {
      expect(crmTaskTabCount(tasks, 'all'), 3);
    });
  });

  group('crmTaskStatusMeta — the card pill', () {
    test('shows the org name and colour, not the folded label', () {
      const lanes = [
        CatalogOption(id: 's-open', name: 'Open', statusType: 'open'),
      ];
      final meta = crmTaskStatusMeta(task(status: 'todo', statusName: 'Open'), lanes);

      expect(meta.label, 'Open', reason: 'not the built-in "To do"');
    });

    test('keeps the org name even when the catalog has not loaded', () {
      final meta = crmTaskStatusMeta(
          task(status: 'blocked', statusName: 'Cancelled'), const []);

      // Name from the row, colour from the bucket it folds into.
      expect(meta.label, 'Cancelled');
    });

    test('a mock row with no name keeps the built-in vocabulary', () {
      final meta = crmTaskStatusMeta(task(status: 'todo'), orgLanes);
      expect(meta.label, 'To do');
    });

    test('a lane deleted since the task was written still renders', () {
      final meta = crmTaskStatusMeta(
          task(status: 'todo', statusName: 'Retired lane'), orgLanes);
      expect(meta.label, 'Retired lane');
    });
  });

  group('the list card schema', () {
    /// The seed org's `?view_type=mobile` config.
    final mobile = ViewSchema.fromResponse({
      'all_fields': {
        'columns': [
          for (final n in ['title', 'status', 'priority', 'due_date', 'assigned_to'])
            {'name': n, 'label': n, 'order': 1, 'visible': true},
          // Configured off for mobile — the card used to show both regardless.
          {'name': 'task_type', 'label': 'Type', 'order': 9, 'visible': false},
          {'name': 'related_to', 'label': 'Related To', 'order': 9, 'visible': false},
        ],
      },
    });

    test('hides the columns the org turned off for mobile', () {
      expect(mobile.shows('task_type'), isFalse);
      expect(mobile.shows('related_to'), isFalse);
    });

    test('keeps the ones it left on', () {
      for (final n in ['title', 'status', 'priority', 'due_date', 'assigned_to']) {
        expect(mobile.shows(n), isTrue, reason: n);
      }
    });

    test('an empty schema shows everything — the built-in card', () {
      // Mock mode, a failed fetch, or an org with no config: "no opinion".
      for (final n in ['task_type', 'related_to', 'status', 'priority']) {
        expect(ViewSchema.empty.shows(n), isTrue, reason: n);
      }
    });
  });
}
