import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/providers/leads_providers.dart';

void main() {
  group('toggleLeadTab (webapp toggleStatusChip)', () {
    test('All clears the selection', () {
      expect(toggleLeadTab({'new', 'won'}, 'all'), isEmpty);
    });

    test('statuses OR-combine and toggle off', () {
      var s = toggleLeadTab(const {}, 'new');
      s = toggleLeadTab(s, 'contacted');
      expect(s, {'new', 'contacted'});
      expect(toggleLeadTab(s, 'new'), {'contacted'});
    });

    test('Other is exclusive both ways', () {
      expect(toggleLeadTab({'new'}, leadOtherTab), {leadOtherTab});
      expect(toggleLeadTab({leadOtherTab}, leadOtherTab), isEmpty);
      expect(toggleLeadTab({leadOtherTab}, 'new'), {'new'});
    });
  });

  test('a dashboard tile pre-selects one chip', () {
    expect(leadTabSelection('all'), isEmpty);
    expect(leadTabSelection('won'), {'won'});
  });

  test('archived rides in the list query and is part of its identity', () {
    final active = leadListQueryFor(const {'x': 1});
    final archived = leadListQueryFor(const {'x': 1}, archived: true);
    expect(archived.filters['is_archive'], true);
    expect(active == archived, isFalse);
  });
}
