// Follow-up types are org-editable, and rows join on the type NAME exactly.
// The app used to hard-code six of them, so against a real org the filter
// offered a type that does not exist ("Payment") and mis-cased one that does
// ("Site visit" vs the org's "Site Visit") — which matched nothing.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/features/crm/application/filters/followups_filter_spec.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/domain/entities/followup.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/crm_catalog_remote_ds.dart';

/// The org's real task priorities — lower-case, as the API sends them.
const _orgPriorities = [
  CatalogOption(id: 'p1', name: 'low'),
  CatalogOption(id: 'p2', name: 'medium'),
  CatalogOption(id: 'p3', name: 'high'),
  CatalogOption(id: 'p4', name: 'critical'),
];

/// Acme's real follow-up types — note "Site Visit" and no "Payment".
const _orgTypes = [
  CatalogOption(id: 't1', name: 'Call'),
  CatalogOption(id: 't2', name: 'Email'),
  CatalogOption(id: 't3', name: 'Meeting'),
  CatalogOption(id: 't4', name: 'WhatsApp'),
  CatalogOption(id: 't5', name: 'Site Visit'),
];

Followup _fu({
  required String kind,
  String status = 'due',
  String priority = '',
}) =>
    Followup(
      priority: priority,
      id: 'F1',
      kind: kind,
      contact: 'Ishaan',
      custId: null,
      leadId: 'L1',
      company: 'DataForge',
      due: '09 Jul 2026',
      time: '10:00',
      status: status,
      owner: 'me',
      title: 'Follow-up',
    );

List<String> _typeOptions({List<CatalogOption> catalog = const []}) {
  final spec = buildFollowupsFilterSpec(typeCatalog: catalog);
  final field = spec.sections.expand((s) => s.fields).firstWhere((f) => f.id == 'types');
  return [for (final o in field.options) o.id];
}

FilterValues _v(Map<String, FilterValue> m) => FilterValues(m);

void main() {
  group('the drawer offers the org’s types', () {
    test('uses the catalog when it has loaded, by name', () {
      expect(_typeOptions(catalog: _orgTypes), ['Call', 'Email', 'Meeting', 'WhatsApp', 'Site Visit']);
    });

    test('no longer offers a type this org does not have', () {
      expect(_typeOptions(catalog: _orgTypes), isNot(contains('Payment')));
    });

    test('falls back to the built-in list when the catalog is empty', () {
      expect(_typeOptions(), kBuiltinFollowupTypes);
    });
  });

  group('matching (mock mode — the API filters server-side)', () {
    test('the org type filters its rows', () {
      expect(followupMatchesFilters(_fu(kind: 'Site Visit'), _v({'types': ChoiceValue(ids: {'Site Visit'})})), isTrue);
      expect(followupMatchesFilters(_fu(kind: 'Call'), _v({'types': ChoiceValue(ids: {'Site Visit'})})), isFalse);
    });

    test('priority matches the folded label the drawer offers', () {
      final spec = buildFollowupsFilterSpec(priorityCatalog: _orgPriorities);
      final ids = spec.sections.expand((s) => s.fields).firstWhere((f) => f.id == 'priorities').options.map((o) => o.id);
      expect(ids, contains('High'));
      expect(followupMatchesFilters(_fu(kind: 'Call', priority: 'high'), _v({'priorities': ChoiceValue(ids: {'High'})})), isTrue);
      expect(followupMatchesFilters(_fu(kind: 'Call', priority: 'low'), _v({'priorities': ChoiceValue(ids: {'High'})})), isFalse);
    });

    test('"is not" on priority excludes the chosen ones', () {
      final v = _v({'priorities': ChoiceValue(ids: {'High'}, isNot: true)});
      expect(followupMatchesFilters(_fu(kind: 'Call', priority: 'high'), v), isFalse);
      expect(followupMatchesFilters(_fu(kind: 'Call', priority: 'low'), v), isTrue);
    });
  });

  group('the catalog fetch', () {
    test('maps rows by follow_up_type_id and name', () {
      final option = CrmCatalogRemoteDataSource.mapCatalogRow(
        const {
          'follow_up_type_id': 'b6157e3e-803b-491b-b182-374293d0afae',
          'name': 'Site Visit',
          'is_active': true,
          'position': 4,
        },
        'follow_up_type_id',
      );

      expect(option!.id, 'b6157e3e-803b-491b-b182-374293d0afae');
      expect(option.name, 'Site Visit');
    });

    test('a nameless row is skipped — it could never match a follow-up', () {
      expect(
        CrmCatalogRemoteDataSource.mapCatalogRow(
            const {'follow_up_type_id': 't9'}, 'follow_up_type_id'),
        isNull,
      );
    });
  });
}
