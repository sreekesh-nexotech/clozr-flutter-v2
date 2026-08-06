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
      agenda: 'Follow-up',
    );

List<String> _typeOptions({List<CatalogOption> catalog = const []}) {
  final spec = buildFollowupsFilterSpec(
    followups: const [],
    typeCatalog: catalog,
  );
  final field = spec.sections
      .expand((s) => s.fields)
      .firstWhere((f) => f.id == 'types');
  return [for (final o in field.options) o.id];
}

List<String> _priorityOptions({List<CatalogOption> catalog = const []}) {
  final spec = buildFollowupsFilterSpec(
    followups: const [],
    priorityCatalog: catalog,
  );
  final fields = spec.sections.expand((s) => s.fields).where((f) => f.id == 'priorities');
  return fields.isEmpty ? const [] : [for (final o in fields.first.options) o.id];
}

void main() {
  group('priority', () {
    test('offers the org spelling, unfolded', () {
      // `Followup.priority` keeps the raw API name, unlike `CrmTask.priority`
      // which is folded to the built-in display vocabulary. Offering "High"
      // here would match nothing on a row carrying "high".
      expect(_priorityOptions(catalog: _orgPriorities),
          ['low', 'medium', 'high', 'critical']);
    });

    test('filters rows by that spelling', () {
      final values = FilterValues()..['priorities'] = ChoiceValue(ids: {'high'});

      expect(followupMatchesFilters(_fu(kind: 'Call', priority: 'high'), values), isTrue);
      expect(followupMatchesFilters(_fu(kind: 'Call', priority: 'low'), values), isFalse);
    });

    test('is negatable like the rest of the drawer', () {
      final values = FilterValues()
        ..['priorities'] = ChoiceValue(ids: {'low'}, isNot: true);

      expect(followupMatchesFilters(_fu(kind: 'Call', priority: 'low'), values), isFalse);
      expect(followupMatchesFilters(_fu(kind: 'Call', priority: 'critical'), values), isTrue);
    });

    test('the section is omitted when the catalog has not loaded', () {
      // An empty checkbox group is a section that can do nothing, and there is
      // no built-in priority vocabulary a follow-up row would match.
      expect(_priorityOptions(), isEmpty);
    });
  });

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

  group('is / is not', () {
    FilterField fieldNamed(String id) => buildFollowupsFilterSpec(
          followups: const [],
          typeCatalog: _orgTypes,
        ).sections.expand((s) => s.fields).firstWhere((f) => f.id == id);

    test('every choice field in the drawer offers the toggle', () {
      for (final id in ['types', 'statuses', 'owners', 'companies']) {
        expect(fieldNamed(id).isNotToggle, isTrue,
            reason: '$id should be negatable');
      }
    });

    test('"is not" on Type excludes the chosen types, keeps the rest', () {
      final values = FilterValues()
        ..['types'] = ChoiceValue(ids: {'Email'}, isNot: true);

      expect(followupMatchesFilters(_fu(kind: 'Email'), values), isFalse);
      expect(followupMatchesFilters(_fu(kind: 'Call'), values), isTrue);
    });

    test('"is not" on Status excludes the chosen statuses', () {
      final values = FilterValues()
        ..['statuses'] = ChoiceValue(ids: {'done'}, isNot: true);

      expect(followupMatchesFilters(_fu(kind: 'Call', status: 'done'), values), isFalse);
      expect(followupMatchesFilters(_fu(kind: 'Call', status: 'due'), values), isTrue);
    });

    test('negating several types excludes all of them', () {
      final values = FilterValues()
        ..['types'] = ChoiceValue(ids: {'Email', 'WhatsApp'}, isNot: true);

      expect(followupMatchesFilters(_fu(kind: 'Email'), values), isFalse);
      expect(followupMatchesFilters(_fu(kind: 'WhatsApp'), values), isFalse);
      expect(followupMatchesFilters(_fu(kind: 'Meeting'), values), isTrue);
    });

    test('flipping to "is not" without picking anything filters nothing', () {
      final values = FilterValues()
        ..['types'] = ChoiceValue(ids: {}, isNot: true);

      expect(followupMatchesFilters(_fu(kind: 'Email'), values), isTrue);
      // …and does not light up the filter badge.
      expect(values.activeCount, 0);
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
