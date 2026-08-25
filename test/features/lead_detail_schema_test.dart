// The lead detail page's information rows come from the org's `detail` layout
// (`/crm/leads/schema/?view_type=detail`), not a hard-coded list. Fixtures here
// are the real shapes returned by the dev backend for two different orgs.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/leads_columns.dart';
import 'package:clozrapp/features/crm/application/record_rows.dart';
import 'package:clozrapp/features/crm/domain/entities/lead.dart';
import 'package:clozrapp/features/crm/domain/entities/lead_schema.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/lead_schema_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

Map<String, dynamic> _col(String name, String label, int order,
        {bool visible = true,
        String type = 'string',
        bool custom = false,
        bool inFields = true}) =>
    {
      'name': name,
      'label': label,
      'order': order,
      'visible': visible,
      'width': 150,
      'is_protected': name == 'lead_name',
      // The server omits `is_fixed` entirely on the detail view — only column
      // and card views mark fixed columns. Absent here on purpose.
      //
      // `field_info` is what marks a column as form-backed: a display-only
      // column (`created_at`) arrives without it.
      if (inFields) 'field_info': {'type': type, 'is_custom': custom},
    };

/// The seeded detail layout, as `?view_type=detail` actually returns it.
final _detailBody = {
  'model': 'Lead',
  'view_type': 'detail',
  'has_org_config': true,
  'all_fields': {
    'columns': [
      _col('lead_name', 'Lead Name', 1),
      _col('organization_name', 'Company Name', 2),
      _col('lead_value', 'Value / Need', 5),
      _col('lead_owner', 'Lead Owner', 7, type: 'foreignkey'),
      _col('lead_source', 'Lead Source', 8, type: 'foreignkey'),
      _col('email', 'Email', 9),
      _col('mobile_no', 'Contact', 10),
      _col('whatsapp_no', 'WhatsApp', 11),
      _col('status', 'Status', 12, type: 'foreignkey'),
      _col('lead_score', 'Lead Score', 13),
      _col('territory', 'Territory', 14, type: 'foreignkey'),
      _col('assignees', 'Assignees', 15, type: 'manytomany'),
      _col('last_followup_at', 'Last Follow-up', 16),
      _col('activity', 'Activity', 17),
      _col('website', 'Website', 20, visible: false),
      _col('industry', 'Industry', 21, visible: false),
      _col('created_at', 'Created On', 22, visible: false),
    ],
  },
};

Lead _lead({
  String email = 'ishaan@example.com',
  String phone = '+917676055470',
  String whatsappNo = '',
  String territory = '',
  String source = 'Website',
  String lastFu = '',
}) =>
    Lead(
      id: 'L1',
      name: 'Ishaan Verma',
      initials: 'IV',
      company: 'DataForge Inc',
      project: 'CRM Pro',
      value: '₹0',
      valueNum: 0,
      status: 'new',
      statusDays: 0,
      score: 23,
      source: source,
      owner: '',
      team: const [],
      phone: phone,
      whatsappNo: whatsappNo,
      territory: territory,
      email: email,
      website: 'www.dataforge.io',
      industry: 'IT / ITES',
      location: 'Kochi',
      createdOn: '05 Aug 2026',
      time: '2d ago',
      lastFu: lastFu,
      notif: 0,
    );

void main() {
  final schema = LeadSchemaRemoteDataSource.mapSchema(_detailBody);

  group('detail schema parsing', () {
    test('keeps the 14 visible columns and drops the hidden ones', () {
      expect(schema.columns.length, 14);
      expect(schema.shows('website'), isFalse);
      expect(schema.shows('industry'), isFalse);
      expect(schema.shows('created_at'), isFalse);
    });

    test('only the name is protected — detail sends no is_fixed at all', () {
      expect(schema.column('lead_name')!.isFixed, isTrue);
      // Everything else is hideable on a detail page, unlike the list view
      // where status/products/assignees are locked.
      expect(schema.column('status')!.isFixed, isFalse);
      expect(schema.column('assignees')!.isFixed, isFalse);
    });
  });

  _editableRowTests();
  _sharedInlineEditTests();

  group('leadDetailRows', () {
    test('renders every visible column, in the org order', () {
      final rows = leadDetailRows(_lead(whatsappNo: '+919000000000',
          territory: 'South', lastFu: 'Call · 2d ago'), schema);

      expect(rows.map((r) => r.label).toList(), [
        'Lead Name',
        'Company Name',
        'Value / Need',
        'Lead Owner',
        'Lead Source',
        'Email',
        'Contact',
        'WhatsApp',
        'Status',
        'Lead Score',
        'Territory',
        'Assignees',
        'Last Follow-up',
        'Activity',
      ]);
      // One row per visible column, hidden ones still dropped.
      expect(rows.length, schema.columns.length);
    });

    test('repeats the columns the page chrome also renders', () {
      // Name / company / value / status / score / owner / assignees appear in
      // the profile, score and people blocks *as well*. This card is a full
      // readout of the org's detail layout, so it carries them too.
      final byLabel = {
        for (final r in leadDetailRows(_lead(), schema)) r.label: r.value
      };

      expect(byLabel['Lead Name'], 'Ishaan Verma');
      expect(byLabel['Company Name'], 'DataForge Inc');
      expect(byLabel['Lead Score'], '23');
      // Visible, but this lead has no owner and no assignees — kept as rows.
      expect(byLabel['Lead Owner'], '—');
      expect(byLabel['Assignees'], '—');
    });

    test('a visible column the lead has no value for shows an em dash', () {
      final rows = leadDetailRows(_lead(), schema); // no whatsapp, no territory

      final byLabel = {for (final r in rows) r.label: r.value};
      expect(byLabel['WhatsApp'], '—');
      expect(byLabel['Territory'], '—');
      expect(byLabel['Last Follow-up'], '—');
      // …while the ones it does have render normally.
      expect(byLabel['Email'], 'ishaan@example.com');
      expect(byLabel['Contact'], '+917676055470');
    });

    test('a column the entity cannot supply is still listed, as an em dash', () {
      // `annual_revenue` has no field on [Lead], so leadColumnText answers
      // null. It used to disappear from the card; now the row is present and
      // labelled, with no value to show.
      final withUnmapped = LeadSchemaRemoteDataSource.mapSchema({
        'has_org_config': true,
        'all_fields': {
          'columns': [_col('annual_revenue', 'Annual Revenue', 1)],
        },
      });

      expect(leadDetailRows(_lead(), withUnmapped).single.value, '—');
    });

    test('uses the org label, so a renamed column renames the row', () {
      final renamed = LeadSchemaRemoteDataSource.mapSchema({
        'has_org_config': true,
        'all_fields': {
          'columns': [_col('mobile_no', 'Primary Phone', 1)],
        },
      });

      expect(leadDetailRows(_lead(), renamed).single.label, 'Primary Phone');
    });

    test('an org custom field renders from the row payload', () {
      final withCustom = LeadSchemaRemoteDataSource.mapSchema({
        'has_org_config': true,
        'all_fields': {
          'columns': [
            _col('custom_fields.budget', 'Budget', 1, type: 'number', custom: true),
            _col('custom_fields.signed', 'Signed', 2, type: 'boolean', custom: true),
          ],
        },
      });
      final lead = LeadsRemoteDataSource.mapLead({
        'lead_id': 'L1',
        'lead_name': 'Ishaan',
        'custom_fields': {'budget': 5000000, 'signed': true},
      })!;

      final rows = leadDetailRows(lead, withCustom);
      expect(rows.map((r) => '${r.label}=${r.value}').toList(),
          ['Budget=5000000', 'Signed=Yes']);
    });

    test('the empty schema yields no rows, so the screen keeps its built-in set', () {
      expect(leadDetailRows(_lead(), LeadListSchema.empty), isEmpty);
    });
  });

  group('detail-only fields reach the entity', () {
    test('whatsapp_no and territory are mapped, and kept apart from phone', () {
      final lead = LeadsRemoteDataSource.mapLead({
        'lead_id': 'L1',
        'lead_name': 'Ishaan',
        'mobile_no': '+911111111111',
        'whatsapp_no': '+912222222222',
        'territory': {'name': 'South', 'territory_id': 't1'},
      })!;

      expect(lead.phone, '+911111111111');
      expect(lead.whatsappNo, '+912222222222');
      expect(lead.territory, 'South');
    });

    test('a list row without them leaves both empty, never null-crashing', () {
      final lead = LeadsRemoteDataSource.mapLead({
        'lead_id': 'L1',
        'lead_name': 'Ishaan',
      })!;

      expect(lead.whatsappNo, '');
      expect(lead.territory, '');
    });
  });
}

/// Long-pressing a Lead-information row edits that field, so each row has to
/// carry the column behind it — the column is what names the API field, gives
/// its type, and says whether it is writable at all.
void _editableRowTests() {
  LeadListSchema schemaOf(List<Map<String, dynamic>> columns) =>
      LeadSchemaRemoteDataSource.mapSchema({
        'has_org_config': true,
        'all_fields': {'columns': columns},
      });

  group('leadDetailRows — editability', () {
    test('every row carries the column behind it', () {
      final rows = leadDetailRows(_lead(), schemaOf([
        _col('lead_name', 'Lead Name', 1),
        _col('email', 'Email', 2, type: 'email'),
      ]));
      expect(rows.map((r) => r.column?.name).toList(), ['lead_name', 'email']);
    });

    test('a typed, form-backed column is editable', () {
      final rows = leadDetailRows(_lead(), schemaOf([
        _col('email', 'Email', 1, type: 'email'),
      ]));
      expect(rows.single.column!.isEditable, isTrue);
    });

    test('a custom field is not — it needs its own write shape', () {
      final rows = leadDetailRows(_lead(), schemaOf([
        _col('budget', 'Budget', 1, type: 'decimal', custom: true),
      ]));
      expect(rows.single.column!.isEditable, isFalse);
    });

    test('a column the schema gives no type is not editable', () {
      // Nothing says how to render or coerce it, so no box is offered.
      final rows = leadDetailRows(_lead(), schemaOf([
        _col('activity', 'Activity', 1, type: ''),
      ]));
      expect(rows.single.column!.isEditable, isFalse);
    });
  });

  group('inline editing — which rows turn into a box', () {
    LeadColumn columnOf(Map<String, dynamic> raw) =>
        LeadSchemaRemoteDataSource.mapSchema({
          'has_org_config': true,
          'all_fields': {'columns': [raw]},
        }).columns.single;

    test('typeable fields do', () {
      for (final type in ['string', 'email', 'url', 'phone', 'text', 'decimal']) {
        expect(leadFieldEditsInline(columnOf(_col('f', 'F', 1, type: type))), isTrue,
            reason: type);
      }
    });

    test('a picker field does not — a text box cannot produce its value', () {
      // A status is an id, a date is an ISO string, a boolean is a flag: typing
      // free text into any of them writes something the API rejects or misreads.
      for (final type in ['foreignkey', 'manytomany', 'date', 'datetime', 'boolean']) {
        expect(leadFieldEditsInline(columnOf(_col('f', 'F', 1, type: type))), isFalse,
            reason: type);
      }
    });

    test('a read-only column never does, whatever its type', () {
      final c = columnOf(_col('created_at', 'Created on', 1,
          type: 'string', inFields: false));
      expect(leadFieldEditsInline(c), isFalse);
    });
  });

  group('inline editing — the hint a blocked row gives back', () {
    LeadColumn columnOf(Map<String, dynamic> raw) =>
        LeadSchemaRemoteDataSource.mapSchema({
          'has_org_config': true,
          'all_fields': {'columns': [raw]},
        }).columns.single;

    test('an editable row has nothing to explain', () {
      expect(leadInlineEditHint(columnOf(_col('email', 'Email', 1, type: 'email'))),
          isNull);
    });

    test('a read-only row says so, by its own label', () {
      final hint = leadInlineEditHint(
          columnOf(_col('created_at', 'Created on', 1, inFields: false)));
      expect(hint, 'Created on is read-only.');
    });

    test('a picker row points at where it can be changed', () {
      final hint = leadInlineEditHint(
          columnOf(_col('status', 'Status', 1, type: 'foreignkey')));
      expect(hint, contains('chosen from a list'));
      expect(hint, contains('Edit lead'));
      expect(hint, startsWith('Status'));
    });

    test('a custom field says it is not supported yet', () {
      final hint = leadInlineEditHint(
          columnOf(_col('budget', 'Budget', 1, type: 'decimal', custom: true)));
      expect(hint, contains('custom field'));
    });

    test('a row with no column behind it still answers', () {
      // The built-in fallback rows, shown when no org layout has loaded.
      expect(leadInlineEditHint(null), isNotNull);
    });
  });
}

/// The gate and the refusal message are shared by five detail screens now, so
/// the module-specific wording is the only thing that varies.
void _sharedInlineEditTests() {
  LeadColumn columnOf(Map<String, dynamic> raw) =>
      LeadSchemaRemoteDataSource.mapSchema({
        'has_org_config': true,
        'all_fields': {'columns': [raw]},
      }).columns.single;

  group('inline editing — shared across modules', () {
    test('the hint names the form that module actually has', () {
      final status = columnOf(_col('status', 'Status', 1, type: 'foreignkey'));
      expect(inlineEditHint(status, editForm: 'Edit quote'),
          contains('use Edit quote'));
      expect(inlineEditHint(status, editForm: 'Edit customer'),
          contains('use Edit customer'));
    });

    test('a read-only row reads the same whichever module asks', () {
      final c = columnOf(_col('created_at', 'Created on', 1, inFields: false));
      expect(inlineEditHint(c, editForm: 'Edit task'), 'Created on is read-only.');
      expect(inlineEditHint(c, editForm: 'Edit follow-up'),
          'Created on is read-only.');
    });

    test('the gate itself does not vary by module', () {
      final typed = columnOf(_col('description', 'Notes', 1, type: 'text'));
      expect(fieldEditsInline(typed), isTrue);
      expect(inlineEditHint(typed, editForm: 'Edit anything'), isNull);
    });
  });
}
