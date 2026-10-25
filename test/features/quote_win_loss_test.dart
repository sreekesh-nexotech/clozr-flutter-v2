import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/domain/entities/quote_win_loss.dart';

void main() {
  // Trimmed from a real dev response (`?date_from=2026-07-27&date_to=2026-10-24`).
  final body = {
    'date_from': '2026-07-27',
    'date_to': '2026-10-24',
    'summary': {
      'total': 13, 'won': 6, 'lost': 1, 'expired': 0, 'open': 6,
      'win_rate': '85.71', 'avg_days_to_accept': '0.03', 'avg_discount_pct': '0.00', 'won_value': '1056483.00',
    },
    'by_owner': [
      {
        'owner_id': '8d8593b8', 'owner_name': 'Ashish Nexotech',
        'total': 13, 'won': 6, 'lost': 1, 'expired': 0, 'open': 6,
        'win_rate': '85.71', 'avg_days_to_accept': '0.03', 'avg_discount_pct': '0.00', 'won_value': '1056483.00',
      },
      {
        'owner_id': null, 'owner_name': null,
        'total': 2, 'won': 0, 'lost': 0, 'expired': 0, 'open': 2,
        'win_rate': null, 'avg_days_to_accept': null, 'avg_discount_pct': null, 'won_value': null,
      },
    ],
    'by_product': [
      {
        'product_id': 'd8da656a', 'product_name': 'App Developent',
        'total': 3, 'won': 0, 'lost': 0, 'expired': 0, 'open': 3,
        'win_rate': null, 'avg_days_to_accept': null, 'avg_discount_pct': '0.00', 'won_value': '0.00',
      },
    ],
    'by_source': [
      {
        'source_id': '7fce9e23', 'source_name': 'Social Media',
        'total': 4, 'won': 3, 'lost': 1, 'expired': 0, 'open': 0,
        'win_rate': '75.00', 'avg_days_to_accept': '0.00', 'avg_discount_pct': '0.00', 'won_value': '409994.00',
      },
    ],
  };

  group('WinLossReport.fromJson', () {
    test('maps the summary as sent — nothing recomputed', () {
      final r = WinLossReport.fromJson(body);
      expect(r.dateFrom, '2026-07-27');
      expect(r.dateTo, '2026-10-24');
      expect(r.summary.total, 13);
      expect(r.summary.won, 6);
      expect(r.summary.lost, 1);
      expect(r.summary.expired, 0);
      expect(r.summary.open, 6);
      expect(r.summary.winRate, '85.71');
      expect(r.summary.avgDaysToAccept, '0.03');
      expect(r.summary.avgDiscountPct, '0.00');
      expect(r.summary.wonValue, '1056483.00');
    });

    test('maps the three breakdowns with their id / name keys', () {
      final r = WinLossReport.fromJson(body);
      expect(r.byOwner.first.key, '8d8593b8');
      expect(r.byOwner.first.name, 'Ashish Nexotech');
      expect(r.byProduct.single.name, 'App Developent');
      expect(r.byProduct.single.winRate, isNull);
      expect(r.bySource.single.name, 'Social Media');
      expect(r.bySource.single.wonValue, '409994.00');
    });

    test('the unassigned bucket gets a blank name, a stable key and safe defaults', () {
      final row = WinLossReport.fromJson(body).byOwner[1];
      expect(row.name, '');
      expect(row.key, 'none-1');
      expect(row.winRate, isNull);
      expect(row.avgDiscountPct, isNull);
      expect(row.wonValue, '0.00');
    });

    test('open-ended range and missing lists', () {
      final r = WinLossReport.fromJson({'date_from': null, 'date_to': null, 'summary': {'total': 0}});
      expect(r.dateFrom, '');
      expect(r.dateTo, '');
      expect(r.summary.total, 0);
      expect(r.summary.winRate, isNull);
      expect(r.byOwner, isEmpty);
      expect(r.byProduct, isEmpty);
      expect(r.bySource, isEmpty);
    });

    test('numeric decimals are carried as strings', () {
      final r = WinLossReport.fromJson({'summary': {'win_rate': 50, 'won_value': 1200.5}});
      expect(r.summary.winRate, '50');
      expect(r.summary.wonValue, '1200.5');
    });

    test('tolerates a non-map body', () {
      expect(WinLossReport.fromJson(null).summary.total, 0);
    });
  });

  group('presets', () {
    final today = DateTime(2026, 10, 24);

    test('Last 30 / 90 days include today', () {
      expect(winLossPresetRange(WinLossPreset.last30, today), (from: '2026-09-25', to: '2026-10-24'));
      expect(winLossPresetRange(WinLossPreset.last90, today), (from: '2026-07-27', to: '2026-10-24'));
    });

    test('This year and All time', () {
      expect(winLossPresetRange(WinLossPreset.thisYear, today), (from: '2026-01-01', to: '2026-10-24'));
      expect(winLossPresetRange(WinLossPreset.allTime, today), (from: '', to: ''));
    });

    test('labels and order match the webapp', () {
      expect(WinLossPreset.quick.map((p) => p.label).toList(),
          ['Last 30 days', 'Last 90 days', 'This year', 'All time']);
    });

    test('query sends only the non-blank bounds', () {
      expect(winLossQuery('', ''), isEmpty);
      expect(winLossQuery('2026-01-01', ''), {'date_from': '2026-01-01'});
      expect(winLossQuery('2026-01-01', '2026-02-01'), {'date_from': '2026-01-01', 'date_to': '2026-02-01'});
    });
  });

  group('winLossRangeError', () {
    test('blank or ordered ranges are fine', () {
      expect(winLossRangeError('', ''), isNull);
      expect(winLossRangeError('2026-01-01', ''), isNull);
      expect(winLossRangeError('', '2026-01-01'), isNull);
      expect(winLossRangeError('2026-01-01', '2026-01-01'), isNull);
      expect(winLossRangeError('2026-01-01', '2026-10-24'), isNull);
    });

    test('from after to', () {
      expect(winLossRangeError('2026-10-10', '2026-01-01'), 'The start date must be on or before the end date.');
    });

    test('malformed or impossible dates', () {
      expect(winLossRangeError('2026-1-1', ''), 'Use a valid date.');
      expect(winLossRangeError('', '24/10/2026'), 'Use a valid date.');
      expect(winLossRangeError('2026-02-31', '2026-03-01'), 'Use a valid date.');
      expect(winLossRangeError('2026-13-01', ''), 'Use a valid date.');
      // An invalid date wins over the ordering check.
      expect(winLossRangeError('2027-01-01', '2026-1-1'), 'Use a valid date.');
    });
  });

  group('labels', () {
    test('win rate', () {
      expect(winRateLabel('85.71'), '85.7%');
      expect(winRateLabel('100.00'), '100%');
      expect(winRateLabel('62.50'), '62.5%');
      expect(winRateLabel(null), '—');
    });

    test('days', () {
      expect(daysLabel('0.03'), '0 days');
      expect(daysLabel('1.00'), '1 day');
      expect(daysLabel('3.50'), '3.5 days');
      expect(daysLabel(null), '—');
    });

    test('discount', () {
      expect(discountLabel('0.00'), '0%');
      expect(discountLabel('12.345'), '12.35%');
      expect(discountLabel('7.50'), '7.5%');
      expect(discountLabel(null), '—');
      expect(discountLabel(''), '—');
    });
  });
}
