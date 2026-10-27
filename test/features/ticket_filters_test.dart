// The tickets list applied its header controls **client-side** over an eagerly
// walked list, so the search box, the My/Breaching chips and the status tab
// could only find a ticket that had already been downloaded. These cover the
// server params that replaced that (`issue-filters.md` Part 4), verified
// against the dev backend.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/helpdesk/application/filters/ticket_query.dart';

/// The org's real catalog: seven statuses, several of which fold onto the same
/// UI tab.
const _catalog = [
  CatalogOption(id: 's-open', name: 'Open'),
  CatalogOption(id: 's-prog', name: 'In Progress'),
  CatalogOption(id: 's-hold', name: 'On Hold'),
  CatalogOption(id: 's-res', name: 'Resolved', isClosed: true),
  CatalogOption(id: 's-closed', name: 'Closed', isClosed: true),
];

void main() {
  group('the header controls become server params', () {
    Map<String, dynamic> params({
      bool mine = false,
      bool breach = false,
      String search = '',
      String tab = 'all',
      Set<String>? chips,
      List<CatalogOption> catalog = _catalog,
      String? savedFilterId,
      bool forCounts = false,
    }) =>
        ticketFilterParamsFor(
          mine: mine,
          breach: breach,
          search: search,
          statusChips: chips ?? (tab == 'all' ? const <String>{} : {tab}),
          catalog: catalog,
          savedFilterId: savedFilterId,
          forCounts: forCounts,
        );

    test('nothing selected sends nothing', () {
      expect(params(), isEmpty);
    });

    test('My Tickets and Breaching are the documented flags', () {
      expect(params(mine: true)['assigned_to_me'], 'true');
      expect(params(breach: true)['sla_breached'], 'true');
    });

    test('search is trimmed and passed through', () {
      expect(params(search: '  permissions ')['search'], 'permissions');
      expect(params(search: '   ').containsKey('search'), isFalse);
    });

    test('a tab sends every status id that folds into it', () {
      // "Open" and "In Progress" both read as the Open tab, and `status__in`
      // takes a csv — so the tab cannot be one id.
      final ids = (params(tab: 'open')['status__in'] as String).split(',');

      expect(ids, containsAll(['s-open', 's-prog']));
      expect(params(tab: 'all').containsKey('status__in'), isFalse);
    });

    test('a tab keyed by the org status id passes it straight through', () {
      // Once the catalog lands the strip is keyed by `issue_status_id`, so the
      // tab is already the value `status__in` wants.
      expect(params(tab: 's-prog')['status__in'], 's-prog');
    });

    test('status chips are multi-select and OR together', () {
      final ids = (params(chips: {'s-open', 's-hold'})['status__in'] as String).split(',');
      expect(ids, containsAll(['s-open', 's-hold']));
    });

    test('My Tickets with no chip hides every resolved status (list only)', () {
      final p = params(mine: true);
      expect(p['assigned_to_me'], 'true');
      expect((p['status__not'] as String).split(','), containsAll(['s-res', 's-closed']));
      // A picked chip shows that status even when resolved.
      expect(params(mine: true, chips: {'s-res'}).containsKey('status__not'), isFalse);
      // The chip counts are the pre-chip scope (webapp baseFilters).
      expect(params(mine: true, forCounts: true).containsKey('status__not'), isFalse);
      expect(params(chips: {'s-open'}, forCounts: true).containsKey('status__in'), isFalse);
    });

    test('an applied saved view is resolved by the server', () {
      expect(params(mine: true, search: ' x ', chips: {'s-open'}, savedFilterId: 'v1'),
          {'saved_filter_id': 'v1', 'search': 'x'});
    });

    test('an unloaded catalog omits the status rather than emptying it', () {
      // Sending an empty `status__in` would return no tickets at all; sending
      // nothing shows every ticket, which the user can see and recover from.
      expect(params(tab: 'open', catalog: const []).containsKey('status__in'),
          isFalse);
    });
  });

  group('the counts endpoint folds onto the tabs', () {
    test('org statuses sharing a tab are summed', () {
      final folded = foldTicketCounts(
        {'all': 25, 's-open': 7, 's-prog': 4, 's-res': 5, 's-closed': 3},
        _catalog,
      );

      expect(folded['all'], 25);
      expect(folded['open'], 11); // Open 7 + In Progress 4
      expect(folded['resolved'], 5);
      expect(folded['closed'], 3);
    });

    test('the raw org ids survive for the id-keyed strip', () {
      // The strip reads org ids once the catalog has loaded and folded keys
      // before it does — one map serves both, and uuids cannot collide with
      // keys like 'open'.
      final folded = foldTicketCounts({'all': 25, 's-prog': 4}, _catalog);

      expect(folded['s-prog'], 4);
      expect(folded['open'], 4);
    });

    test('an empty answer stays empty, so the strip counts locally', () {
      expect(foldTicketCounts(const {}, _catalog), isEmpty);
    });
  });

  group('status folding', () {
    test('maps org names onto the UI tab keys', () {
      expect(ticketStatusIdsFor('resolved', _catalog), ['s-res']);
      expect(ticketStatusIdsFor('closed', _catalog), ['s-closed']);
      // A key no org status folds into yields nothing, not everything.
      expect(ticketStatusIdsFor('new', _catalog), isEmpty);
    });
  });

  // The drawer used to be applied purely client-side, so a facet could only
  // narrow rows already downloaded.
  group('the drawer facets that map become server params', () {
    Map<String, dynamic> encode(void Function(FilterValues v) set) {
      final values = FilterValues();
      set(values);
      return ticketDrawerParams(values, _catalog);
    }

    test('status selections send the org ids that fold into them', () {
      final p = encode((v) => v['statuses'] = ChoiceValue(ids: {'open'}));

      final ids = (p['status__in'] as String).split(',');
      expect(ids, containsAll(['s-open', 's-prog']));
    });

    test('priority is translated to the API vocabulary', () {
      // The app says Urgent where the API stores Critical.
      final p = encode((v) => v['pri'] = ChoiceValue(ids: {'Urgent', 'High'}));

      final names = (p['priority__in'] as String).split(',');
      expect(names, containsAll(['Critical', 'High']));
      expect(names, isNot(contains('Urgent')));
    });

    test('the SLA facet maps only its stored flag', () {
      expect(
        encode((v) => v['sla'] = const RadioValue(id: 'breached', defaultId: 'any'))['sla_breached'],
        'true',
      );
      // "Due < 1h" is computed off the clock — no param exists for it, so it
      // stays with the client matcher rather than being silently dropped.
      expect(
        encode((v) => v['sla'] = const RadioValue(id: 'risk', defaultId: 'any')),
        isEmpty,
      );
    });

    test('linked work maps tasks only', () {
      expect(
        encode((v) => v['linked'] = const RadioValue(id: 'task', defaultId: 'any'))['has_linked_tasks'],
        'true',
      );
      // The API has no "has linked project" filter.
      expect(
        encode((v) => v['linked'] = const RadioValue(id: 'proj', defaultId: 'any')),
        isEmpty,
      );
    });

    test('category, product, project and customer send their uuids', () {
      expect(encode((v) => v['cats'] = ChoiceValue(ids: {'t1'})), {'issue_type__in': 't1'});
      expect(encode((v) => v['products'] = ChoiceValue(ids: {'p1'})), {'product__in': 'p1'});
      expect(encode((v) => v['projects'] = ChoiceValue(ids: {'j1'})), {'project__in': 'j1'});
      expect(encode((v) => v['companies'] = ChoiceValue(ids: {'c1', 'c2'}))['customer__in'], 'c1,c2');
    });

    test('an is-not selection uses the __not param the server honours', () {
      // The webapp sends __not_in, which the backend ignores (DEF-HD-012).
      expect(encode((v) => v['pri'] = ChoiceValue(ids: {'High'}, isNot: true)), {'priority__not': 'High'});
      expect(encode((v) => v['statuses'] = ChoiceValue(ids: {'s-open'}, isNot: true)), {'status__not': 's-open'});
      expect(encode((v) => v['companies'] = ChoiceValue(ids: {'c1'}, isNot: true)), {'customer__not': 'c1'});
    });
  });

  group('the board sections open the list on themselves', () {
    // "+N more" used to `go(Routes.tickets)` bare, landing on whatever the list
    // last showed — with My Tickets on by default, tapping it under Breached
    // could open a list holding none of those tickets.
    test('every board key maps onto a drawer SLA facet', () {
      expect(ticketSlaFacetForBoard('breached'), 'breached');
      expect(ticketSlaFacetForBoard('today'), 'today');
      expect(ticketSlaFacetForBoard('ontrack'), 'ontrack');
    });

    test('the one key whose names differ still translates', () {
      expect(ticketSlaFacetForBoard('lt1h'), 'risk');
    });

    test('anything that is not a section maps to nothing', () {
      expect(ticketSlaFacetForBoard('paused'), isNull);
      expect(ticketSlaFacetForBoard(''), isNull);
    });

    test('the breached facet is the only one the server can narrow', () {
      final drawer = FilterValues()
        ..['sla'] = const RadioValue(id: 'breached', defaultId: 'any');
      expect(ticketDrawerParams(drawer, const []), {'sla_breached': 'true'});

      // Clock-based buckets have no documented param, so they must not invent
      // one — the client matcher resolves them over whatever the server sends.
      for (final id in ['risk', 'today', 'ontrack']) {
        final v = FilterValues()..['sla'] = RadioValue(id: id, defaultId: 'any');
        expect(ticketDrawerParams(v, const []), isEmpty, reason: id);
      }
    });
  });

}
