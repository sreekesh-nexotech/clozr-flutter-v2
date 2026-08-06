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

/// Acme's real follow-up types — note "Site Visit" and no "Payment".
const _orgTypes = [
  CatalogOption(id: 't1', name: 'Call'),
  CatalogOption(id: 't2', name: 'Email'),
  CatalogOption(id: 't3', name: 'Meeting'),
  CatalogOption(id: 't4', name: 'WhatsApp'),
  CatalogOption(id: 't5', name: 'Site Visit'),
];

Followup _fu({required String kind}) => Followup(
      id: 'F1',
      kind: kind,
      contact: 'Ishaan',
      custId: null,
      leadId: 'L1',
      company: 'DataForge',
      due: '09 Jul 2026',
      time: '10:00',
      status: 'due',
      owner: 'me',
      agenda: 'Follow-up',
    );

List<String> _typeOptions({List<CatalogOption> catalog = const []}) {
  final spec = buildFollowupsFilterSpec(
    leads: const [],
    customers: const [],
    followups: const [],
    typeCatalog: catalog,
  );
  final field = spec.sections
      .expand((s) => s.fields)
      .firstWhere((f) => f.id == 'types');
  return [for (final o in field.options) o.id];
}

void main() {
  group('the drawer offers the org’s types', () {
    test('uses the catalog when it has loaded', () {
      expect(_typeOptions(catalog: _orgTypes),
          ['Call', 'Email', 'Meeting', 'WhatsApp', 'Site Visit']);
    });

    test('no longer offers a type this org does not have', () {
      final options = _typeOptions(catalog: _orgTypes);

      expect(options, isNot(contains('Payment')),
          reason: 'the hard-coded list invented it');
    });

    test('spells the type exactly as the org does', () {
      final options = _typeOptions(catalog: _orgTypes);

      // Matching is an exact string compare, so the old 'Site visit' could
      // never match a row carrying 'Site Visit'.
      expect(options, contains('Site Visit'));
      expect(options, isNot(contains('Site visit')));
    });

    test('falls back to the built-in list when the catalog is empty', () {
      expect(_typeOptions(), kBuiltinFollowupTypes);
    });
  });

  group('matching against the org spelling', () {
    test('the org type now filters its rows', () {
      final values = FilterValues()
        ..['types'] = ChoiceValue(ids: {'Site Visit'});

      expect(followupMatchesFilters(_fu(kind: 'Site Visit'), values), isTrue);
      expect(followupMatchesFilters(_fu(kind: 'Call'), values), isFalse);
    });

    test('the old hard-coded spelling matched nothing — why this mattered', () {
      final values = FilterValues()
        ..['types'] = ChoiceValue(ids: {'Site visit'});

      expect(followupMatchesFilters(_fu(kind: 'Site Visit'), values), isFalse);
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
