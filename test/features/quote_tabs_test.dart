// The Quotes status chips carry a count each. They used to be built from an
// over-tolerant predicate — a row matched a tab by its org status *name* OR by
// the folded built-in key — so a quote could belong to two tabs at once and the
// numbers stopped adding up. These pin the arithmetic.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/providers/quotes_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/quote.dart';

/// [status] is the folded key the mapper derived (date-aware: a sent quote past
/// its validity arrives as `expired`); [statusName] is the org's own name, as
/// the API sent it.
Quote _quote(String id, {required String status, String statusName = ''}) =>
    Quote(
      id: id,
      custId: null,
      leadId: 'l1',
      status: status,
      statusName: statusName,
      amount: '₹1L',
      amountNum: 100000,
      issued: '01 Jun 2026',
      valid: '01 Jul 2026',
      template: 'Standard',
      payType: 'Lump sum',
      currency: 'INR',
      dueDate: '—',
      owner: 'me',
      items: const [],
    );

/// The built-in vocabulary, used before `/quotations/statuses/` lands.
const _builtIn = {'draft', 'sent', 'accepted', 'rejected', 'expired'};

int _sum(List<Quote> quotes, Set<String> keys) =>
    keys.fold(0, (n, k) => n + quoteTabCount(quotes, k, tabKeys: keys));

void main() {
  group('a quote is counted under exactly one tab', () {
    test('a sent quote past its validity is not counted twice', () {
      // The mapper folds it to `expired` while the API still calls it "Sent" —
      // it matched the Sent tab by name and the Expired tab by folded key.
      final quotes = [_quote('Q1', status: 'expired', statusName: 'Sent')];

      expect(quoteTabCount(quotes, 'sent', tabKeys: _builtIn), 1);
      expect(quoteTabCount(quotes, 'expired', tabKeys: _builtIn), 0);
      expect(_sum(quotes, _builtIn), quotes.length);
    });

    test('the chips add up to All across a mixed list', () {
      final quotes = [
        _quote('Q1', status: 'draft', statusName: 'Draft'),
        _quote('Q2', status: 'expired', statusName: 'Sent'),
        _quote('Q3', status: 'accepted', statusName: 'Accepted'),
        _quote('Q4', status: 'sent'), // mock row: no name at all
        _quote('Q5', status: 'draft', statusName: 'Under Review'),
      ];

      expect(quoteTabCount(quotes, 'all', tabKeys: _builtIn), 5);
      expect(_sum(quotes, _builtIn), 5);
    });
  });

  group('the org’s own vocabulary', () {
    const orgKeys = {'draft', 'sent', 'under review', 'accepted'};

    test('a row is counted under its org status, whatever it folds into', () {
      // "Under Review" folds into the `draft` bucket, but the pill shows the
      // org's name, so the org's tab is where it belongs.
      final quotes = [_quote('Q1', status: 'draft', statusName: 'Under Review')];

      expect(quoteTabCount(quotes, 'under review', tabKeys: orgKeys), 1);
      expect(quoteTabCount(quotes, 'draft', tabKeys: orgKeys), 0);
    });

    test('matching is case-insensitive on both sides', () {
      final quotes = [_quote('Q1', status: 'sent', statusName: 'Sent')];

      // The chips carry the catalog's own casing ("Sent"), the folded keys are
      // lower-case. A case-sensitive compare made this clause dead.
      expect(quoteTabCount(quotes, 'Sent', tabKeys: orgKeys), 1);
    });

    test('a status the tab row does not offer falls back to its bucket', () {
      // The org deleted "Legacy" since this quote was written, so it has no
      // chip. It still folds into `draft` and is counted there rather than
      // vanishing from every tab while staying in the All count.
      final quotes = [_quote('Q1', status: 'draft', statusName: 'Legacy')];

      expect(quoteTabCount(quotes, 'draft', tabKeys: orgKeys), 1);
      expect(_sum(quotes, orgKeys), 1);
    });
  });

  test('the All tab counts every row', () {
    final quotes = [
      _quote('Q1', status: 'draft', statusName: 'Draft'),
      _quote('Q2', status: 'sent'),
    ];

    expect(quoteTabCount(quotes, 'all', tabKeys: _builtIn), 2);
    expect(quoteInTab(quotes.first, 'all', tabKeys: _builtIn), isTrue);
  });
}
