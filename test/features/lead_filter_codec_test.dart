import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/features/crm/application/filters/lead_filter_codec.dart';
import 'package:clozrapp/features/crm/application/filters/leads_filter_spec.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/saved_filters_remote_ds.dart';

CatalogOption opt(String id, String name, {String? type}) =>
    CatalogOption(id: id, name: name, statusType: type);

final _statuses = [
  opt('st-new', 'New', type: 'new'),
  opt('st-con', 'Contacted', type: 'in_progress'),
  opt('st-lost', 'Lost', type: 'lost'),
];
final _sources = [opt('src-web', 'Website'), opt('src-ref', 'Referral')];
final _products = [opt('p-pro', 'NexoCRM Pro')];
final _teams = [opt('tm-north', 'Team North')];

const _meUuid = 'user-me-uuid';

LeadFilterCodec codec({bool withCatalogs = true}) => withCatalogs
    ? LeadFilterCodec(
        statuses: _statuses,
        sources: _sources,
        products: _products,
        teams: _teams,
        currentUserId: _meUuid,
      )
    : const LeadFilterCodec(currentUserId: _meUuid);

/// A spec carrying the org catalogs, so option ids match what the codec emits.
FilterSpec spec() => buildLeadsFilterSpec(
      const [],
      statusCatalog: _statuses,
      sourceCatalog: _sources,
      productCatalog: _products,
      teamCatalog: _teams,
    );

void main() {
  // The codec resolves date chips against the filter clock; pin it so the
  // encoded range is stable regardless of when the suite runs.
  setUp(() => filterNow = () => DateTime(2026, 8, 6));
  tearDown(() => filterNow = defaultFilterNow);

  group('encode → LeadFilter params', () {
    test('maps every drawer section to its documented param name', () {
      final v = spec().defaults();
      v['sources'] = ChoiceValue(ids: {'Website'});
      v['stages'] = ChoiceValue(ids: {'contacted'}, isNot: true);
      v['products'] = ChoiceValue(ids: {'NexoCRM Pro'});
      v['teams'] = ChoiceValue(ids: {'tm-north'});
      v['owners'] = ChoiceValue(ids: {'me'});
      v['aging'] = const RadioValue(id: '30', defaultId: 'any');
      v['ownerMode'] = const RadioValue(id: 'none', defaultId: 'all');
      v['value'] = const RangeValue(min: 5, max: 20);
      v['score'] = const RadioValue(id: 'hot', defaultId: 'all');

      expect(codec().encode(v), {
        'lead_source__in': 'src-web',
        'product__in': 'p-pro',
        'status__not': 'st-con', // the is-not toggle picks the __not param
        'assigned_team__in': 'tm-north',
        'assignees__in': _meUuid, // the 'me' sentinel becomes a real uuid
        'stale_days': 30,
        'owner_mode': 'unassigned',
        'lead_value_min': 500000, // lakhs → raw rupees
        'lead_value_max': 2000000,
        'lead_score_min': 75,
      });
    });

    test('a date chip resolves to the concrete range it means now', () {
      final v = spec().defaults();
      v['created'] = const DateValue(chip: 'last7');
      expect(codec().encode(v), {
        'created_at_after': '2026-07-30',
        'created_at_before': '2026-08-06',
      });
    });

    test('score buckets follow the documented ranges', () {
      Map<String, dynamic> enc(String id) {
        final v = spec().defaults();
        v['score'] = RadioValue(id: id, defaultId: 'all');
        return codec().encode(v);
      }

      expect(enc('hot'), {'lead_score_min': 75});
      expect(enc('warm'), {'lead_score_min': 45, 'lead_score_max': 74});
      expect(enc('cold'), {'lead_score_max': 44});
    });

    test('an all-defaults draft encodes to {} — the API rejects saving that', () {
      expect(codec().encode(spec().defaults()), isEmpty);
    });

    test('a value the catalog no longer knows is dropped, not sent as a name', () {
      final v = spec().defaults();
      v['sources'] = ChoiceValue(ids: {'Website', 'Deleted Source'});
      expect(codec().encode(v), {'lead_source__in': 'src-web'});
    });

    test('when every selected value is unresolvable the key is omitted', () {
      final v = spec().defaults();
      v['sources'] = ChoiceValue(ids: {'Deleted Source'});
      expect(codec().encode(v), isEmpty);
    });
  });

  group('decode → drawer state', () {
    test('round-trips a full definition back to the same values', () {
      final v = spec().defaults();
      v['sources'] = ChoiceValue(ids: {'Website', 'Referral'});
      v['stages'] = ChoiceValue(ids: {'contacted'}, isNot: true);
      v['teams'] = ChoiceValue(ids: {'tm-north'});
      v['owners'] = ChoiceValue(ids: {'me'});
      v['aging'] = const RadioValue(id: '14', defaultId: 'any');
      v['ownerMode'] = const RadioValue(id: 'me', defaultId: 'all');
      v['value'] = const RangeValue(min: 5, max: 20);
      v['score'] = const RadioValue(id: 'warm', defaultId: 'all');

      final back = codec().decode(codec().encode(v), spec());

      expect(back.choice('sources')!.ids, {'Website', 'Referral'});
      expect(back.choice('stages')!.ids, {'contacted'});
      expect(back.choice('stages')!.isNot, isTrue);
      expect(back.choice('teams')!.ids, {'tm-north'});
      expect(back.choice('owners')!.ids, {'me'}); // uuid recognised as self
      expect(back.radio('aging')!.id, '14');
      expect(back.radio('ownerMode')!.id, 'me');
      expect(back.range('value'), const RangeValue(min: 5, max: 20));
      expect(back.radio('score')!.id, 'warm');
    });

    test('accepts the repeated-param array form as well as "a,b"', () {
      final back = codec().decode({
        'lead_source__in': ['src-web', 'src-ref'],
      }, spec());
      expect(back.choice('sources')!.ids, {'Website', 'Referral'});
    });

    test('a chip comes back as the absolute range it was saved as', () {
      final v = spec().defaults();
      v['created'] = const DateValue(chip: 'last7');
      final back = codec().decode(codec().encode(v), spec());
      expect(back.date('created')!.chip, isNull); // documented loss
      expect(back.date('created')!.from, DateTime(2026, 7, 30));
      expect(back.date('created')!.to, DateTime(2026, 8, 6));
    });

    test('a score range outside the three buckets is dropped, not guessed', () {
      final back = codec().decode({'lead_score_min': 10, 'lead_score_max': 90}, spec());
      expect(back.radio('score')!.isActive, isFalse);
    });

    test('a stage the org deleted does not resurrect as an inert chip', () {
      final back = codec().decode({'status__in': 'st-purged'}, spec());
      expect(back.choice('stages')?.isActive ?? false, isFalse);
    });

    test('an unknown key is ignored rather than throwing', () {
      final back = codec().decode({'something_new': 'x', 'lead_score_min': 75}, spec());
      expect(back.radio('score')!.id, 'hot');
    });
  });

  test('with no catalogs (mock mode) ids pass through and round-trip', () {
    final mock = codec(withCatalogs: false);
    final s = buildLeadsFilterSpec(const []);
    final v = s.defaults();
    v['stages'] = ChoiceValue(ids: {'won'});
    final def = mock.encode(v);
    expect(def, {'status__in': 'won'});
    expect(mock.decode(def, s).choice('stages')!.ids, {'won'});
  });

  group('saved filter row mapping', () {
    test('maps the documented response shape', () {
      final f = SavedFiltersRemoteDataSource.mapSavedFilter({
        'saved_filter_id': 'sf-1',
        'module': 'lead',
        'name': 'Hot North-team leads',
        'filter_definition': {'lead_score_min': 75},
        'is_valid': true,
        'invalid_reason': null,
        'order': 0,
      })!;
      expect(f.id, 'sf-1');
      expect(f.name, 'Hot North-team leads');
      expect(f.definition, {'lead_score_min': 75});
      expect(f.isValid, isTrue);
    });

    test('carries the server-set invalid flag through', () {
      final f = SavedFiltersRemoteDataSource.mapSavedFilter({
        'saved_filter_id': 'sf-2',
        'name': 'Broken',
        'filter_definition': {'custom_fields.budget': 1},
        'is_valid': false,
        'invalid_reason': 'custom_fields.budget',
      })!;
      expect(f.isValid, isFalse);
      expect(f.invalidReason, 'custom_fields.budget');
    });

    test('a row without an id or name is skipped', () {
      expect(SavedFiltersRemoteDataSource.mapSavedFilter({'name': 'x'}), isNull);
      expect(
        SavedFiltersRemoteDataSource.mapSavedFilter({'saved_filter_id': 'a', 'name': ' '}),
        isNull,
      );
    });
  });
}
