import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/data/mock/status_meta.dart';
import 'package:clozrapp/features/crm/application/filters/leads_filter_spec.dart';
import 'package:clozrapp/features/crm/application/providers/crm_catalog_providers.dart';
import 'package:clozrapp/features/crm/application/providers/leads_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/domain/entities/lead.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/crm_catalog_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

/// The Ivtern dev org's real `/crm/lead-statuses/` payload — eight stages,
/// two of which ("Contacted", "Proposal Sent") have no built-in equivalent.
List<Map<String, dynamic>> statusRows() => [
      {'lead_status_id': 's0', 'name': 'New', 'status_type': 'new', 'color': '#3B82F6'},
      {'lead_status_id': 's1', 'name': 'Contacted', 'status_type': 'in_progress', 'color': '#8B5CF6'},
      {'lead_status_id': 's2', 'name': 'Qualified', 'status_type': 'in_progress', 'color': '#F59E0B'},
      {'lead_status_id': 's3', 'name': 'Proposal Sent', 'status_type': 'in_progress', 'color': '#F97316'},
      {'lead_status_id': 's4', 'name': 'Negotiation', 'status_type': 'in_progress', 'color': '#EC4899'},
      {'lead_status_id': 's5', 'name': 'Won', 'status_type': 'won', 'color': '#10B981'},
      {'lead_status_id': 's6', 'name': 'Lost', 'status_type': 'lost', 'color': '#EF4444'},
      {'lead_status_id': 's7', 'name': 'Disqualified', 'status_type': 'junk', 'color': '#6B7280'},
    ];

List<CatalogOption> statusCatalog() => [
      for (final r in statusRows())
        CrmCatalogRemoteDataSource.mapCatalogRow(r, 'lead_status_id', withType: true)!,
    ];

Lead leadWith({required String status, String statusName = ''}) => Lead(
      id: 'l-$status-$statusName',
      name: 'Test Lead',
      initials: 'TL',
      company: null,
      project: '',
      value: '₹0',
      valueNum: 0,
      status: status,
      statusName: statusName,
      statusDays: 0,
      score: 0,
      source: 'Website',
      owner: 'me',
      team: const [],
      phone: '',
      email: '',
      website: '',
      industry: '',
      location: '',
      createdOn: '01 Jan 2026',
      time: '1h ago',
      lastFu: '',
      notif: 0,
    );

void main() {
  group('catalog row mapping', () {
    test('maps name, hex colour and status_type', () {
      final o = CrmCatalogRemoteDataSource.mapCatalogRow(
          statusRows()[1], 'lead_status_id', withType: true)!;
      expect(o.id, 's1');
      expect(o.name, 'Contacted');
      expect(o.statusType, 'in_progress');
      expect(o.color, const Color(0xFF8B5CF6));
      expect(o.key, 'contacted');
    });

    test('a nameless row is skipped — it could never join to a lead row', () {
      expect(
        CrmCatalogRemoteDataSource.mapCatalogRow({'lead_status_id': 'x', 'name': '  '}, 'lead_status_id'),
        isNull,
      );
    });

    test('statusType is only read when asked for (sources have none)', () {
      final o = CrmCatalogRemoteDataSource.mapCatalogRow(
          {'lead_source_id': 'src', 'name': 'Website', 'color': '#3B82F6'}, 'lead_source_id')!;
      expect(o.statusType, isNull);
      expect(o.color, const Color(0xFF3B82F6));
    });

    test('hexColor handles #RGB, bare hex, blank and junk', () {
      expect(hexColor('#FFF'), const Color(0xFFFFFFFF));
      expect(hexColor('3B82F6'), const Color(0xFF3B82F6));
      expect(hexColor(''), isNull);
      expect(hexColor('red'), isNull);
      expect(hexColor(null), isNull);
    });
  });

  group('Lead.stageKey picks one vocabulary', () {
    test('API mode: the org name, not the bucket it folds into', () {
      expect(leadWith(status: 'qualified', statusName: 'Contacted').stageKey, 'contacted');
    });

    test('mock mode: the built-in key', () {
      expect(leadWith(status: 'new').stageKey, 'new');
    });

    test('never both — a folded lead must not also match the org bucket tab', () {
      // Regression: a union of both vocabularies made this lead match the
      // org's own "Qualified" tab as well as "Contacted", double-counting it.
      expect(leadWith(status: 'qualified', statusName: 'Contacted').stageKey, isNot('qualified'));
    });
  });

  group('status tabs', () {
    test('a Contacted lead counts under Contacted only, never twice', () {
      final base = [
        leadWith(status: 'qualified', statusName: 'Contacted'),
        leadWith(status: 'qualified', statusName: 'Qualified'),
      ];
      expect(leadTabCount(base, 'contacted'), 1);
      expect(leadTabCount(base, 'qualified'), 1);
      expect(leadTabCount(base, 'all'), 2);
      // Every lead lands in exactly one stage tab.
      final perTab = ['contacted', 'qualified'].map((k) => leadTabCount(base, k));
      expect(perTab.reduce((a, b) => a + b), base.length);
    });

    test('mock leads still count under the built-in keys', () {
      final base = [leadWith(status: 'won'), leadWith(status: 'won'), leadWith(status: 'lost')];
      expect(leadTabCount(base, 'won'), 2);
      expect(leadTabCount(base, 'lost'), 1);
    });
  });

  group('stage vocabulary resolution', () {
    test('tier 1 — the org catalog, in server order, with its colours', () {
      final v = leadStageVocabulary(statusCatalog(), const []);
      expect(v.map((t) => t.label).toList(),
          ['New', 'Contacted', 'Qualified', 'Proposal Sent', 'Negotiation', 'Won', 'Lost', 'Disqualified']);
      expect(v[1].id, 'contacted');
      expect(v[1].color, const Color(0xFF8B5CF6));
    });

    test('tier 2 — catalog failed: derive the stages the loaded leads name', () {
      final leads = [
        leadWith(status: 'qualified', statusName: 'Contacted'),
        leadWith(status: 'won', statusName: 'Won'),
        leadWith(status: 'qualified', statusName: 'Contacted'),
      ];
      final v = leadStageVocabulary(const [], leads);
      expect(v.map((t) => t.label).toList(), ['Contacted', 'Won']); // deduped, pipeline order
      // Crucially the ids still match what the leads report, so tabs count.
      expect(leadTabCount(leads, v.first.id), 2);
    });

    test('tier 3 — mock mode falls back to the seven built-ins', () {
      final v = leadStageVocabulary(const [], [leadWith(status: 'new')]);
      expect(v.length, 7);
      expect(v.map((t) => t.id), contains('quote'));
    });
  });

  group('status pill resolution', () {
    test('uses the org name and colour, so Contacted stays Contacted', () {
      final meta = leadStatusMeta(
          leadWith(status: 'qualified', statusName: 'Contacted'), statusCatalog());
      expect(meta.label, 'Contacted');
      expect(meta.color, const Color(0xFF8B5CF6));
    });

    test('catalog empty: keeps the org name, so the pill matches its tab', () {
      final meta =
          leadStatusMeta(leadWith(status: 'qualified', statusName: 'Contacted'), const []);
      expect(meta.label, 'Contacted');
      expect(meta.color, StatusMeta$.lead['qualified']!.color); // bucket colour
    });

    test('a stage the catalog no longer lists still shows its real name', () {
      final meta = leadStatusMeta(
          leadWith(status: 'new', statusName: 'Some Removed Stage'), statusCatalog());
      expect(meta.label, 'Some Removed Stage');
    });

    test('mock leads, which name no stage, use the built-in label', () {
      expect(leadStatusMeta(leadWith(status: 'won'), const []).label, 'Won');
    });

    test('a stage with no colour set borrows its bucket colour', () {
      final o = CrmCatalogRemoteDataSource.mapCatalogRow(
          {'lead_status_id': 'x', 'name': 'Demo Call', 'status_type': 'won', 'color': ''},
          'lead_status_id',
          withType: true)!;
      expect(o.color, isNull);
      expect(leadStatusColor(o), isNotNull);
    });
  });

  group('filter spec Stage section', () {
    test('offers the org stages when the catalog loaded', () {
      final spec = buildLeadsFilterSpec(const [], statusCatalog: statusCatalog());
      final stages = spec.fieldById('stages')!.options;
      expect(stages.map((o) => o.label).toList(), [
        'New', 'Contacted', 'Qualified', 'Proposal Sent',
        'Negotiation', 'Won', 'Lost', 'Disqualified',
      ]);
      expect(stages.map((o) => o.id), contains('proposal sent'));
    });

    test('falls back to the seven built-ins when the catalog is empty', () {
      final stages = buildLeadsFilterSpec(const []).fieldById('stages')!.options;
      expect(stages.length, 7);
      expect(stages.map((o) => o.id), contains('quote'));
    });

    test('a Contacted stage filter matches only the Contacted lead', () {
      final spec = buildLeadsFilterSpec(const [], statusCatalog: statusCatalog());
      final values = spec.defaults();
      values['stages'] = ChoiceValue(ids: {'contacted'});
      expect(leadMatchesFilters(leadWith(status: 'qualified', statusName: 'Contacted'), values), isTrue);
      expect(leadMatchesFilters(leadWith(status: 'qualified', statusName: 'Qualified'), values), isFalse);
    });
  });

  group('filter spec Source and Product sections', () {
    test('use the org catalogs, including options no loaded lead uses', () {
      final sources = [
        CrmCatalogRemoteDataSource.mapCatalogRow(
            {'lead_source_id': 'a', 'name': 'Website'}, 'lead_source_id')!,
        CrmCatalogRemoteDataSource.mapCatalogRow(
            {'lead_source_id': 'b', 'name': 'Trade Show'}, 'lead_source_id')!,
      ];
      final products = [
        CrmCatalogRemoteDataSource.mapCatalogRow(
            {'product_id': 'p1', 'product_name': 'NexoCRM Pro'}, 'product_id',
            nameKey: 'product_name')!,
        CrmCatalogRemoteDataSource.mapCatalogRow(
            {'product_id': 'p2', 'product_name': 'WhatsApp Integration'}, 'product_id',
            nameKey: 'product_name')!,
      ];
      final spec = buildLeadsFilterSpec(
        const [],
        sourceCatalog: sources,
        productCatalog: products,
      );
      expect(spec.fieldById('sources')!.options.map((o) => o.label), ['Website', 'Trade Show']);
      expect(spec.fieldById('products')!.options.map((o) => o.label),
          ['NexoCRM Pro', 'WhatsApp Integration']);
    });

    test('still derive from the loaded leads when the catalogs are empty', () {
      final spec = buildLeadsFilterSpec([leadWith(status: 'new')]);
      expect(spec.fieldById('sources')!.options.map((o) => o.label), ['Website']);
      // The lead's empty `project` must not become a blank option row.
      expect(spec.fieldById('products')!.options, isEmpty);
    });
  });

  test('mapLead keeps the raw status name alongside the folded key', () {
    final lead = LeadsRemoteDataSource.mapLead({
      'lead_id': 'l1',
      'lead_name': 'Testing call',
      'status': 'Contacted',
    }, statusTypes: {'contacted': 'in_progress'})!;
    expect(lead.statusName, 'Contacted');
    expect(lead.status, 'qualified'); // the built-in bucket, unchanged
    expect(lead.stageKey, 'contacted');
  });
}
