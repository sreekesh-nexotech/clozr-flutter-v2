// The task "Task information" panel is now the org's `view_type=detail` layout
// over the raw record, instead of six hard-coded rows (one of which was the
// literal string "3 days ago"). Fixtures are the live shapes for this org.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/record_rows.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';

Map<String, dynamic> _col(String name, String label, int order, String type) => {
      'name': name,
      'label': label,
      'order': order,
      'visible': true,
      'is_protected': name == 'title',
      'field_info': {'type': type},
    };

/// The org's seeded task detail layout, as the live endpoint returns it.
final _schema = ViewSchema.fromResponse({
  'model': 'task',
  'view_type': 'detail',
  'has_org_config': true,
  'all_fields': {
    'columns': [
      _col('title', 'Task', 1, 'string'),
      _col('task_type', 'Type', 2, 'string'),
      _col('status', 'Status', 3, 'foreignkey'),
      _col('priority', 'Priority', 4, 'foreignkey'),
      _col('due_date', 'Due Date', 5, 'date'),
      _col('due_time', 'Due Time', 6, 'time'),
      _col('duration', 'Duration', 7, 'integer'),
      _col('assigned_team', 'Assigned Team', 8, 'foreignkey'),
      _col('related_to', 'Related To', 9, ''),
      _col('description', 'Description', 10, 'text'),
      _col('assigned_to', 'Assigned To', 11, 'foreignkey'),
      _col('assignees', 'Assignees', 12, 'manytomany'),
    ],
  },
});

/// A record as `GET /crm/tasks/{id}/` returns it.
const _row = {
  'task_id': 'T1',
  'title': 'Call the lead',
  'task_type': 'Call',
  'status': {'name': 'Open', 'status_type': 'open'},
  'priority': {'name': 'critical'},
  'due_date': '2026-07-09',
  'due_time': '10:30:00',
  'duration': 30,
  'assigned_team': null,
  'related_to': {'lead_name': 'Rahul Verma 48'},
  'description': 'Confirm the revised scope before the site visit.',
  'assigned_to': {'full_name': 'Admin Acme'},
  'assignees': [
    {'full_name': 'Admin Acme'},
    {'full_name': 'Amit Pandey'},
  ],
};

void main() {
  group('rows follow the org layout', () {
    test('renders every visible column, in order, under the org labels', () {
      final rows = recordRows(_row, _schema, skip: const {'title'});

      expect(rows.map((r) => r.label).toList(), [
        'Type',
        'Status',
        'Priority',
        'Due Date',
        'Due Time',
        'Duration',
        'Assigned Team',
        'Related To',
        'Description',
        'Assigned To',
        'Assignees',
      ]);
    });

    test('carries the column name so a screen can key an icon off it', () {
      final rows = recordRows(_row, _schema, skip: const {'title'});

      expect(rows.first.name, 'task_type');
    });

    test('repeats what the page also renders in its own chrome', () {
      // The header shows the title and the Description tab shows the body; the
      // panel is a full readout of the org's layout, so it carries them too.
      final rows = recordRows(_row, _schema);

      expect(rows.first.label, 'Task');
      expect(rows.any((r) => r.label == 'Description'), isTrue);
      expect(rows.length, _schema.columns.length);
    });

    test('skip is still honoured when a caller asks for it', () {
      final rows = recordRows(_row, _schema, skip: const {'title', 'description'});

      expect(rows.any((r) => r.label == 'Description'), isFalse);
    });

    test('the empty schema yields nothing, so the panel keeps built-in rows', () {
      expect(recordRows(_row, ViewSchema.empty), isEmpty);
    });
  });

  group('values are formatted by the type the schema reports', () {
    Map<String, String> byLabel() => {
          for (final r in recordRows(_row, _schema, skip: const {'title'}))
            r.label: r.value
        };

    test('foreign keys read their nested name, not the object', () {
      expect(byLabel()['Status'], 'Open');
      expect(byLabel()['Priority'], 'critical');
      expect(byLabel()['Assigned To'], 'Admin Acme');
    });

    test('related_to resolves through its record name', () {
      expect(byLabel()['Related To'], 'Rahul Verma 48');
    });

    test('many-to-many joins its members', () {
      expect(byLabel()['Assignees'], 'Admin Acme, Amit Pandey');
    });

    test('dates and times are display-formatted, seconds dropped', () {
      // `absoluteDate`'s house format — day is not zero-padded.
      expect(byLabel()['Due Date'], '9 Jul 2026');
      expect(byLabel()['Due Time'], '10:30');
    });

    test('an integer keeps no trailing decimal', () {
      expect(byLabel()['Duration'], '30');
      expect(recordValueText(30.0, 'integer'), '30');
    });

    test('a null value renders an em dash, not an empty row', () {
      expect(byLabel()['Assigned Team'], '—');
    });
  });

  group('robustness', () {
    test('a column the payload does not carry at all still renders, as a dash', () {
      // Layout and payload disagreeing is worth surfacing as "nothing here";
      // dropping the row would hide the disagreement.
      final rows = recordRows(const {'title': 'x', 'task_type': 'Call'}, _schema,
          skip: const {'title'});

      expect(rows.length, _schema.columns.length - 1);
      final byLabel = {for (final r in rows) r.label: r.value};
      expect(byLabel['Type'], 'Call');
      expect(byLabel['Due Date'], '—');
      expect(byLabel['Assignees'], '—');
    });

    test('a key present as null still renders — that is real information', () {
      final rows = recordRows(
          const {'task_type': null}, _schema, skip: const {'title'});

      expect(rows.firstWhere((r) => r.name == 'task_type').value, '—');
    });

    test('an unrecognised nested object degrades to a dash, never a Map dump', () {
      expect(recordValueText(const {'unexpected': 1}, 'foreignkey'), '—');
    });

    test('custom fields read out of the custom_fields object', () {
      final schema = ViewSchema.fromResponse({
        'has_org_config': true,
        'all_fields': {
          'columns': [
            {
              'name': 'custom_fields.budget',
              'label': 'Budget',
              'order': 1,
              'visible': true,
              'field_info': {'type': 'number', 'is_custom': true},
            },
          ],
        },
      });

      final rows = recordRows(const {
        'custom_fields': {'budget': 5000},
      }, schema);

      expect(rows.single.value, '5000');
    });
  });
}
