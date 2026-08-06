// The lead detail page's information rows come from the org's `detail` layout
// (`/crm/leads/schema/?view_type=detail`), not a hard-coded list. Fixtures here
// are the real shapes returned by the dev backend for two different orgs.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/leads_columns.dart';
import 'package:clozrapp/features/crm/domain/entities/lead.dart';
import 'package:clozrapp/features/crm/domain/entities/lead_schema.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/lead_schema_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

Map<String, dynamic> _col(String name, String label, int order,
        {bool visible = true, String type = 'string', bool custom = false}) =>
    {
      'name': name,
      'label': label,
      'order': order,
      'visible': visible,
      'width': 150,
      'is_protected': name == 'lead_name',
      // The server omits `is_fixed` entirely on the detail view — only column
      // and card views mark fixed columns. Absent here on purpose.
      'field_info': {'type': type, 'is_custom': custom},
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

  group('leadDetailRows', () {
    test('renders exactly the fields the page chrome does not already show', () {
      final rows = leadDetailRows(_lead(whatsappNo: '+919000000000',
          territory: 'South', lastFu: 'Call · 2d ago'), schema);

      expect(rows.map((r) => r.label).toList(), [
        'Lead Source',
        'Email',
        'Contact',
        'WhatsApp',
        'Territory',
        'Last Follow-up',
        'Activity',
      ]);
      // Name / company / value / status / score / owner / assignees are the
      // profile, score and people blocks — never repeated as rows.
      expect(rows.any((r) => r.label == 'Lead Name'), isFalse);
      expect(rows.any((r) => r.label == 'Lead Score'), isFalse);
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
