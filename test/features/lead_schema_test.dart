// The Leads list card is laid out by the org's own column config
// (`/crm/leads/schema/`). These cover the two halves: parsing that config, and
// turning a column into the text the card shows — including the org's custom
// fields, and the "empty schema means built-in layout" fallback the whole
// screen depends on.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/leads_columns.dart';
import 'package:clozrapp/features/crm/domain/entities/lead.dart';
import 'package:clozrapp/features/crm/domain/entities/lead_schema.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/lead_schema_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

Map<String, dynamic> _column(
  String name, {
  required bool visible,
  String? label,
  int order = 1,
  bool custom = false,
  String type = 'text',
  bool fixed = false,
}) =>
    {
      'name': name,
      'label': label ?? name,
      'order': order,
      'visible': visible,
      'width': 150,
      'is_protected': fixed,
      'is_fixed': fixed,
      'field_info': {'type': type, 'is_custom': custom},
    };

Map<String, dynamic> _schemaBody(List<Map<String, dynamic>> columns,
        {bool hasOrgConfig = true}) =>
    {
      'model': 'Lead',
      'view_type': 'mobile',
      'has_org_config': hasOrgConfig,
      'all_fields': {'columns': columns},
    };

Lead _lead({
  String value = '₹18L',
  int score = 0,
  String source = '',
  String email = '',
  Map<String, Object?> customFields = const {},
}) =>
    Lead(
      id: 'L1',
      name: 'Ramesh Pillai',
      initials: 'RP',
      company: 'Kalyan Silks',
      project: 'Showroom interiors',
      value: value,
      valueNum: 1800000,
      status: 'new',
      statusDays: 0,
      score: score,
      source: source,
      owner: '',
      team: const [],
      phone: '',
      email: email,
      website: '',
      industry: '',
      location: '',
      createdOn: '',
      time: '2h ago',
      lastFu: '',
      notif: 0,
      customFields: customFields,
    );

void main() {
  group('LeadSchemaRemoteDataSource.mapSchema', () {
    test('keeps visible columns in order and drops hidden ones', () {
      final schema = LeadSchemaRemoteDataSource.mapSchema(_schemaBody([
        _column('lead_value', visible: true, order: 4),
        _column('lead_name', visible: true, order: 1, fixed: true),
        _column('email', visible: false, order: 2),
        _column('status', visible: true, order: 3),
      ]));

      expect(schema.columns.map((c) => c.name).toList(),
          ['lead_name', 'status', 'lead_value']);
      expect(schema.shows('email'), isFalse);
      expect(schema.hasOrgConfig, isTrue);
      expect(schema.column('lead_name')!.isFixed, isTrue);
    });

    test('carries the org label and recognises custom columns', () {
      final schema = LeadSchemaRemoteDataSource.mapSchema(_schemaBody([
        _column('lead_source', visible: true, label: 'Channel', order: 1),
        _column('custom_fields.budget',
            visible: true, label: 'Budget', order: 2, custom: true, type: 'number'),
      ]));

      expect(schema.labelOf('lead_source', 'Source'), 'Channel');
      final budget = schema.column('custom_fields.budget')!;
      expect(budget.isCustom, isTrue);
      expect(budget.customKey, 'budget');
      expect(budget.type, 'number');
    });

    test('a column without an explicit visible flag is not shown', () {
      final schema = LeadSchemaRemoteDataSource.mapSchema(_schemaBody([
        {'name': 'email', 'label': 'Email', 'order': 1},
      ]));

      expect(schema.isEmpty, isTrue);
    });

    test('an unusable body maps to the empty schema, never an error', () {
      expect(LeadSchemaRemoteDataSource.mapSchema(null).isEmpty, isTrue);
      expect(LeadSchemaRemoteDataSource.mapSchema('nope').isEmpty, isTrue);
      expect(LeadSchemaRemoteDataSource.mapSchema(<String, dynamic>{}).isEmpty, isTrue);
      expect(
        LeadSchemaRemoteDataSource.mapSchema({'all_fields': {'columns': 'bad'}}).isEmpty,
        isTrue,
      );
    });
  });

  group('the empty schema is the built-in layout', () {
    test('shows every field, so nothing is hidden before it loads', () {
      const schema = LeadListSchema.empty;

      expect(schema.shows('lead_value'), isTrue);
      expect(schema.shows('organization_name'), isTrue);
      expect(schema.showsAny(const ['products', 'lead_source']), isTrue);
      // …and adds no chips, so the card looks exactly as it did before.
      expect(leadExtraColumns(_lead(score: 88), schema), isEmpty);
    });
  });

  group('leadExtraColumns', () {
    test('skips what the card already renders and keeps the org order', () {
      final schema = LeadSchemaRemoteDataSource.mapSchema(_schemaBody([
        _column('lead_name', visible: true, order: 1),
        _column('lead_value', visible: true, order: 2),
        _column('custom_fields.budget',
            visible: true, label: 'Budget', order: 3, custom: true, type: 'number'),
        _column('lead_score', visible: true, label: 'Score', order: 4),
      ]));

      final extras = leadExtraColumns(
        _lead(score: 77, customFields: {'budget': 5000000}),
        schema,
      );

      // lead_name / lead_value are frame slots — never repeated as chips.
      expect(extras.map((e) => e.label).toList(), ['Budget', 'Score']);
      expect(extras.map((e) => e.value).toList(), ['5000000', '77']);
    });

    test('a visible column with no value for this lead is dropped', () {
      final schema = LeadSchemaRemoteDataSource.mapSchema(_schemaBody([
        _column('email', visible: true, label: 'Email', order: 1),
        _column('custom_fields.gstin',
            visible: true, label: 'GSTIN', order: 2, custom: true),
        _column('territory', visible: true, label: 'Territory', order: 3),
      ]));

      // Empty built-in, an unset custom field (the API keys it as null), and a
      // column the entity does not carry.
      final extras = leadExtraColumns(
        _lead(email: '', customFields: {'gstin': null}),
        schema,
      );

      expect(extras, isEmpty);
    });
  });

  group('leadColumnText formats by the type the schema reports', () {
    String? textFor(Object? value, String type) => leadColumnText(
          _lead(customFields: {'f': value}),
          LeadColumn(
            name: 'custom_fields.f',
            label: 'F',
            order: 1,
            type: type,
            isCustom: true,
          ),
        );

    test('booleans, dates, lists and whole decimals', () {
      expect(textFor(true, 'boolean'), 'Yes');
      expect(textFor(false, 'boolean'), 'No');
      expect(textFor('2026-03-15T10:00:00Z', 'date'), '15 Mar 2026');
      expect(textFor(['A', 'B'], 'multi_select'), 'A, B');
      expect(textFor(5000.0, 'decimal'), '5000');
      expect(textFor('  ', 'text'), isNull);
      expect(textFor(null, 'text'), isNull);
    });
  });

  group('LeadsRemoteDataSource.mapLead', () {
    test('carries custom_fields through verbatim', () {
      final lead = LeadsRemoteDataSource.mapLead({
        'lead_id': 'L1',
        'lead_name': 'Ramesh',
        'custom_fields': {'budget': 1800000, 'gstin': null},
      })!;

      expect(lead.customFields, {'budget': 1800000, 'gstin': null});
    });

    test('a row with no custom_fields object yields an empty map', () {
      final lead = LeadsRemoteDataSource.mapLead({
        'lead_id': 'L1',
        'lead_name': 'Ramesh',
      })!;

      expect(lead.customFields, isEmpty);
    });
  });
}
