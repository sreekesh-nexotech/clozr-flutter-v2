import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

/// A trimmed `GET /crm/leads/schema/?view_type=detail` body, in the real shape:
/// `all_fields.columns` mixes editable serializer fields with display-only ones.
const _schemaBody = {
  'model': 'Lead',
  'view_type': 'detail',
  'has_org_config': true,
  'all_fields': {
    'columns': [
      {
        'name': 'lead_name',
        'label': 'Lead Name',
        'order': 1,
        'visible': true,
        'is_protected': true,
        'in_fields': true,
        'field_info': {'name': 'lead_name', 'type': 'string'},
      },
      {
        // Visible and labelled, but not a serializer field — the API accepts a
        // write to it, returns 200 and stores nothing.
        'name': 'lead_value',
        'label': 'Value / Need',
        'order': 5,
        'visible': true,
        'is_protected': false,
        'in_fields': false,
      },
      {
        'name': 'lead_source',
        'label': 'Lead Source',
        'order': 8,
        'visible': true,
        'in_fields': true,
        'field_info': {
          'name': 'lead_source',
          'type': 'foreignkey',
          'related_model': 'LeadSource',
          'related_field': 'lead_source_id',
        },
      },
      {
        'name': 'status',
        'label': 'Status',
        'order': 12,
        'visible': true,
        'in_fields': true,
        'field_info': {
          'name': 'status',
          'type': 'foreignkey',
          'related_model': 'LeadStatus',
        },
      },
      {
        'name': 'assignees',
        'label': 'Assignees',
        'order': 15,
        'visible': true,
        'in_fields': true,
        'field_info': {
          'name': 'assignees',
          'type': 'manytomany',
          'related_model': 'User',
        },
      },
      {
        // Hidden by the org — never rendered.
        'name': 'created_at',
        'label': 'Created On',
        'order': 6,
        'visible': false,
        'in_fields': false,
      },
    ],
  },
};

void main() {
  final schema = ViewSchema.fromResponse(_schemaBody);

  group('editableColumns', () {
    test('keeps only serializer-backed fields, in the org order', () {
      expect(
        schema.editableColumns.map((c) => c.name),
        ['lead_name', 'lead_source', 'status', 'assignees'],
      );
    });

    test('drops a visible but display-only column', () {
      // `lead_value` is the one that made the old form look like it saved a
      // deal value it never did.
      expect(schema.shows('lead_value'), isTrue, reason: 'still displayed');
      expect(
        schema.editableColumns.any((c) => c.name == 'lead_value'),
        isFalse,
        reason: 'but never editable — in_fields is false',
      );
    });

    test('drops hidden columns entirely', () {
      expect(schema.shows('created_at'), isFalse);
    });
  });

  group('column metadata', () {
    test('carries the org label and the FK target model', () {
      final source = schema.column('lead_source')!;
      expect(source.label, 'Lead Source');
      expect(source.relatedModel, 'LeadSource');
      expect(source.isChoice, isTrue);
      expect(source.isMulti, isFalse);
    });

    test('a manytomany column reports itself as multi', () {
      final assignees = schema.column('assignees')!;
      expect(assignees.isChoice, isTrue);
      expect(assignees.isMulti, isTrue);
      expect(assignees.relatedModel, 'User');
    });

    test('field_info alone is enough to mark a column editable', () {
      // Some payloads carry `field_info` without an explicit `in_fields`.
      final s = ViewSchema.fromResponse({
        'all_fields': {
          'columns': [
            {
              'name': 'email',
              'label': 'Email',
              'order': 1,
              'visible': true,
              'field_info': {'name': 'email', 'type': 'string'},
            },
          ],
        },
      });
      expect(s.editableColumns.single.name, 'email');
    });
  });

  group('writeKeyFor', () {
    test('status writes to status_id, not status', () {
      // The serializer exposes `status` read-only as the display name: writing
      // to it returns 200 and changes nothing. Verified against a live org.
      expect(
        LeadsRemoteDataSource.writeKeyFor(schema.column('status')!),
        'status_id',
      );
    });

    test('every other field writes under its own name', () {
      expect(
        LeadsRemoteDataSource.writeKeyFor(schema.column('lead_source')!),
        'lead_source',
      );
      expect(
        LeadsRemoteDataSource.writeKeyFor(schema.column('lead_name')!),
        'lead_name',
      );
      expect(
        LeadsRemoteDataSource.writeKeyFor(schema.column('assignees')!),
        'assignees',
      );
    });
  });

  group('an empty schema', () {
    test('has nothing to render, which is what triggers the built-in form', () {
      expect(ViewSchema.empty.editableColumns, isEmpty);
    });

    test('a body with no all_fields block parses to empty rather than throwing',
        () {
      expect(ViewSchema.fromResponse({'model': 'Lead'}).editableColumns, isEmpty);
      expect(ViewSchema.fromResponse(null).editableColumns, isEmpty);
    });
  });
}
