import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/crm_catalog_remote_ds.dart';
import 'package:clozrapp/features/crm/presentation/components/duplicate_notice.dart';
import 'package:clozrapp/features/crm/presentation/components/sla_clocks_section.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('territory tree: parents first, children indented, groups disabled', () {
    final t = CrmCatalogRemoteDataSource.territoryTree([
      {'territory_id': 'k', 'name': 'Kochi', 'parent_territory': 'r'},
      {'territory_id': 'r', 'name': 'Region', 'is_group': true},
      {'territory_id': 'x', 'name': 'Orphan', 'parent_territory': 'missing'},
    ]);
    expect(t.map((o) => (o.name, o.depth, o.disabled)).toList(),
        [('Region', 0, true), ('Kochi', 1, false), ('Orphan', 0, false)]);
  });

  test('duplicate block parses matches and key text', () {
    final d = LeadDuplicate.parse({
      'type': 'duplicate',
      'match_keys': ['email', 'phone'],
      'matched': {
        'leads': [
          {'lead_id': 'l1', 'lead_name': 'Ana', 'email': 'a@x.com'}
        ],
      },
    })!;
    expect(d.keysText, 'email or phone');
    expect(d.leads.single.name, 'Ana');
    expect(LeadDuplicate.parse({'type': 'other'}), isNull);
    expect(LeadDuplicate.fromWarnings([{'match_keys': ['email', 'phone', 'mobile_no']}])!.keysText,
        'email, phone or mobile number');
  });

  test('SLA chip text and states', () {
    final now = DateTime.parse('2026-10-23T10:00:00Z');
    expect(
        SlaClockChip.fromJson({'layer': 'performance', 'target': 'first_touch', 'state': 'running', 'remaining_seconds': 8100}, now: now)!.text,
        'Team · First touch — 2h 15m left');
    final b = SlaClockChip.fromJson({'layer': 'commitment', 'target': 'idle', 'state': 'running', 'remaining_seconds': -11400}, now: now)!;
    expect((b.state, b.text), (SlaChipState.breached, 'Client · Idle — Overdue 3h 10m'));
    expect(SlaClockChip.fromJson({'layer': 'performance', 'target': 'idle', 'state': 'cancelled'}), isNull);
  });

  test('custom field columns map to form controls', () {
    final c = ViewColumn.fromJson({
      'name': 'custom_fields.note',
      'visible': true,
      'field_info': {'type': 'text', 'is_custom': true, 'is_required': true},
    })!;
    expect((c.type, c.isRequired, c.customType, c.customKey), ('string', true, 'text', 'note'));
  });
}
