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
  CatalogOption(id: 's-res', name: 'Resolved'),
  CatalogOption(id: 's-closed', name: 'Closed'),
];

void main() {
  group('the header controls become server params', () {
    Map<String, dynamic> params({
      bool mine = false,
      bool breach = false,
      String search = '',
      String tab = 'all',
      List<CatalogOption> catalog = _catalog,
    }) =>
        ticketFilterParamsFor(
          mine: mine,
          breach: breach,
          search: search,
          statusTab: tab,
          catalog: catalog,
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

    test('name-keyed facets are left to the client matcher', () {
      // Category / company / product options are display names; the API filters
      // on uuids, so sending a name would match nothing at all.
      expect(encode((v) => v['cats'] = ChoiceValue(ids: {'Complaint'})), isEmpty);
      expect(encode((v) => v['companies'] = ChoiceValue(ids: {'Acme'})), isEmpty);
      expect(encode((v) => v['products'] = ChoiceValue(ids: {'Router'})), isEmpty);
    });

    test('an is-not selection is not translated', () {
      // `__not` params exist, but the client matcher already expresses this and
      // mixing the two risks a double negative.
      final p = encode(
          (v) => v['pri'] = ChoiceValue(ids: {'High'}, isNot: true));

      expect(p, isEmpty);
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
