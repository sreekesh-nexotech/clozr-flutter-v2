// The Add role sheet collected a visibility scope and a set of capability
// ticks, then posted a hard-coded `[{group: crm, visibility: hierarchy}]` —
// every role came out the same regardless of the form. These cover the body it
// now builds and the catalog that populates the form. Fixtures are the shapes
// in `docs-flutter/roles.md` §1 and §3.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/people/domain/entities/module_catalog.dart';
import 'package:clozrapp/features/people/infrastructure/data_sources/remote/people_remote_ds.dart';

final _catalogBody = {
  'groups': [
    {
      'key': 'crm',
      'label': 'CRM',
      'description': 'Leads, customers, quotes & payments',
      'coming_soon': false,
      'modules': [
        {'module_name': 'lead', 'label': 'Lead'},
      ],
    },
    {
      'key': 'pmo',
      'label': 'PMO',
      'description': 'Projects & project tasks',
      'coming_soon': false,
      'modules': [
        {'module_name': 'project', 'label': 'Project'},
      ],
    },
    {
      'key': 'helpdesk',
      'label': 'Helpdesk',
      'description': 'Tickets',
      'coming_soon': true,
      'modules': <Object>[],
    },
  ],
  'visibility_scopes': [
    {'value': 'all', 'label': 'All Records'},
    {'value': 'owned', 'label': 'Owned Records'},
    {'value': 'assignee', 'label': 'Assigned Records'},
    {'value': 'team', 'label': 'Team Records'},
    {'value': 'hierarchy', 'label': 'Hierarchy Records'},
    {'value': 'filtered', 'label': 'Filtered Records'},
  ],
};

void main() {
  group('the create body carries what the form was set to', () {
    test('one module_groups entry per ticked card, at the chosen scope', () {
      final body = PeopleRemoteDataSource.roleCreateBody(
        name: 'Regional Lead',
        description: 'Runs the south zone',
        groups: {'crm', 'pmo'},
        visibility: 'team',
      );

      expect(body['name'], 'Regional Lead');
      expect(body['description'], 'Runs the south zone');
      expect(body['module_groups'], [
        {'group': 'crm', 'visibility': 'team'},
        {'group': 'pmo', 'visibility': 'team'},
      ]);
    });

    test('the scope is the code, never the label the chip shows', () {
      final body = PeopleRemoteDataSource.roleCreateBody(
          name: 'R', groups: {'crm'}, visibility: 'hierarchy');

      // "Self + Reporting Hierarchy" is display; `hierarchy` is what is stored.
      expect((body['module_groups'] as List).single,
          {'group': 'crm', 'visibility': 'hierarchy'});
      expect(kRoleScopeLabels['hierarchy'], 'Self + Reporting Hierarchy');
    });

    test('a blank description is omitted rather than sent empty', () {
      final blank = PeopleRemoteDataSource.roleCreateBody(
          name: 'R', description: '   ', groups: {'crm'});

      expect(blank.containsKey('description'), isFalse);
    });

    test('nothing ticked omits module_groups instead of sending []', () {
      // A supplied `module_groups` is the complete grant set, so `[]` would be
      // an explicit "grant nothing" rather than "say nothing".
      final body = PeopleRemoteDataSource.roleCreateBody(name: 'R');

      expect(body.containsKey('module_groups'), isFalse);
    });
  });

  group('the module catalog drives the form', () {
    final catalog = ModuleCatalog.fromJson(_catalogBody);

    test('groups keep their key, label, blurb and coming-soon flag', () {
      expect([for (final g in catalog.groups) g.key], ['crm', 'pmo', 'helpdesk']);
      expect(catalog.groups.first.label, 'CRM');
      expect(catalog.groups.first.description, 'Leads, customers, quotes & payments');
      expect(catalog.groups.first.comingSoon, isFalse);
      // Rendered locked — granting one is a 400.
      expect(catalog.groups.last.comingSoon, isTrue);
    });

    test('scopes read in the app’s vocabulary, not the server’s', () {
      final byValue = {for (final s in catalog.scopes) s.value: s};

      // The role cards say "Organization-wide"; the API says "All Records".
      // The form has to agree with the card it will produce.
      expect(byValue['all']!.displayLabel, 'Organization-wide');
      expect(byValue['team']!.displayLabel, 'Team-based + Reporting Hierarchy');
    });

    test('filtered is not offered — the form cannot build a filter', () {
      final offered = [for (final s in catalog.offerableScopes) s.value];

      expect(offered, isNot(contains('filtered')));
      expect(offered, containsAll(['all', 'hierarchy', 'team']));
    });

    test('a broken response degrades to the built-in card set', () {
      expect(ModuleCatalog.fromJson({'unexpected': true}).isEmpty, isTrue);
      expect(ModuleCatalog.fromJson(null).isEmpty, isTrue);
      // Which is what the sheet falls back to, and it is still postable.
      expect([for (final g in ModuleCatalog.builtIn.groups) g.key],
          ['crm', 'pmo']);
      expect(ModuleCatalog.builtIn.isEmpty, isFalse);
    });

    test('a group with no key is dropped rather than posted as blank', () {
      final partial = ModuleCatalog.fromJson({
        'groups': [
          {'label': 'Nameless'},
          {'key': 'crm', 'label': 'CRM'},
        ],
        'visibility_scopes': [
          {'value': 'all', 'label': 'All Records'},
        ],
      });

      expect([for (final g in partial.groups) g.key], ['crm']);
    });
  });
}
