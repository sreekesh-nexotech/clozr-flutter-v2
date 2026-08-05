import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/app/router/routes.dart';
import 'package:clozrapp/app/theme/app_colors.dart';
import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/data/mock/mock_users.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/crm_home_remote_ds.dart';

void main() {
  tearDown(UserDirectory.reset);

  group('CRM home KPIs', () {
    test('maps values, unit-carrying empties, trend polarity and progress', () {
      final (cards, firstResponse) = CrmHomeRemoteDataSource.mapKpis({
        'new_leads': {'count': 142, 'trend_pct': 18.3},
        'win_rate': {'pct': 23.0, 'trend_pct': 4.3},
        'first_response': {'median_minutes': 14, 'trend_pct': 3.0},
        'quote_acceptance': {'pct': 52.0, 'trend_pct': 5.0},
        'quote_to_cash_days': {'median_days': 42, 'trend_pct': -3.0},
      });

      // New leads — good-when-up, rising → green pill, up arrow.
      expect(cards[0].value, '142');
      expect(cards[0].unit, '');
      expect(cards[0].trend, '+18.3%');
      expect(cards[0].trendUp, isTrue);
      expect(cards[0].arrowUp, isTrue);
      expect(cards[0].progress, isNull);

      // Win rate — percentage unit.
      expect(cards[1].value, '23');
      expect(cards[1].unit, '%');
      expect(cards[1].trend, '+4.3%');
      expect(cards[1].trendUp, isTrue);

      // Quote to cash — bad-when-up; a drop (-3%) is an improvement → green
      // pill but a down arrow.
      expect(cards[2].value, '42');
      expect(cards[2].unit, 'days');
      expect(cards[2].trend, '-3%');
      expect(cards[2].trendUp, isTrue);
      expect(cards[2].arrowUp, isFalse);

      // Quote acceptance — percentage with a progress bar.
      expect(cards[3].value, '52');
      expect(cards[3].unit, '%');
      expect(cards[3].progress, closeTo(0.52, 0.0001));

      // First-response median feeds the trend card headline.
      expect(firstResponse, 14);
    });

    test('missing metrics keep their unit but zero out (never mock)', () {
      final (cards, firstResponse) = CrmHomeRemoteDataSource.mapKpis(const {});
      expect(cards, hasLength(4));
      expect(cards[0].value, '0');
      expect(cards[1].unit, '%'); // win rate keeps its fixed unit
      expect(cards[1].trend, isNull);
      expect(cards[2].unit, 'days');
      expect(cards[3].unit, '%');
      expect(firstResponse, isNull);
    });
  });

  group('CRM home funnel', () {
    test('maps org stages, parses hex, derives tab keys and colour fallbacks', () {
      final bars = CrmHomeRemoteDataSource.mapFunnel({
        'crm': {
          'stages': [
            {'name': 'New', 'color': '#074ADB', 'count': 10},
            {'name': 'Won', 'color': 'bogus', 'count': 3},
            {'name': 'Custom Stage', 'count': 1},
          ],
        },
      });

      expect(bars, hasLength(3));
      expect(bars[0].label, 'New');
      expect(bars[0].count, 10);
      expect(bars[0].color, const Color(0xFF074ADB));
      expect(bars[0].tabKey, 'new');
      // Unparseable hex → the stage's fallback colour.
      expect(bars[1].tabKey, 'won');
      expect(bars[1].color, AppColors.pending);
      // Unknown stage → 'all' drill-down + neutral navy.
      expect(bars[2].tabKey, 'all');
      expect(bars[2].color, AppColors.navy);
    });

    test('absent funnel → empty (no bars)', () {
      expect(CrmHomeRemoteDataSource.mapFunnel(null), isEmpty);
    });
  });

  group('CRM home attention (missed)', () {
    test('renders direction labels + signed deltas, empties missing metrics', () {
      final attn = CrmHomeRemoteDataSource.mapMissed({
        'payments_missed': {'count': 12, 'trend_pct': 3.0, 'direction': 'worsening'},
        'followups_missed': {'count': 28, 'trend_pct': 0.0, 'direction': 'steady'},
        'tasks_missed': {'count': 19, 'trend_pct': -5.0, 'direction': 'improving'},
        // lost_after_quote absent → neutral empty card.
      });

      expect(attn[0].value, '12');
      expect(attn[0].delta, '+3%');
      expect(attn[0].up, isFalse);
      expect(attn[0].neutral, isFalse);
      expect(attn[0].note, 'Worsening');
      expect(attn[0].noteColor, AppColors.error);

      expect(attn[1].delta, '0');
      expect(attn[1].neutral, isTrue);
      expect(attn[1].note, 'Steady');

      expect(attn[2].up, isTrue);
      expect(attn[2].note, 'Improving');
      expect(attn[2].delta, '-5%');

      expect(attn[3].value, '0');
      expect(attn[3].note, '');
      expect(attn[3].neutral, isTrue);
    });
  });

  group('CRM home recent wins (undocumented shape)', () {
    test('probes nested/flat keys, money fallbacks, lead vs customer routing', () {
      final (wins, count, total) = CrmHomeRemoteDataSource.mapWins({
        'results': [
          {
            'customer': {'name': 'Kalyan Silks'},
            'deal': 'Showroom interiors',
            'amount': '1800000.00',
            'won_at': '2026-06-28T10:00:00Z',
            'lead_id': 'L1001',
          },
          {
            'name': 'Paragon Restaurant',
            'value': 1800000,
            'customer_id': 'C2012',
            'type': 'customer',
          },
          {'foo': 'bar'}, // no resolvable name → dropped
        ],
      });

      expect(wins, hasLength(2));
      expect(count, 2);
      expect(total, closeTo(3600000.0, 0.001));

      expect(wins[0].name, 'Kalyan Silks');
      expect(wins[0].deal, 'Showroom interiors');
      expect(wins[0].amt, '₹18L');
      expect(wins[0].when, startsWith('Won '));
      expect(wins[0].route, Routes.leadDetail);
      expect(wins[0].id, 'L1001');

      expect(wins[1].name, 'Paragon Restaurant');
      expect(wins[1].route, Routes.customerDetail);
      expect(wins[1].id, 'C2012');
    });

    test('unparseable body → empty (never mock)', () {
      expect(CrmHomeRemoteDataSource.mapWins(null).$1, isEmpty);
      expect(CrmHomeRemoteDataSource.mapWins({'x': 1}).$2, 0);
    });
  });

  group('CRM home stuck items', () {
    test('maps title/owner/value(money vs passthrough)/age + per-chip route', () {
      final rows = CrmHomeRemoteDataSource.mapStuck({
        'items': [
          {'id': 'q1', 'title': 'Workafella Coworking', 'owner': 'Deepak Raj', 'value': '18400000.00', 'stuck_days': 8},
          {'id': 'q2', 'title': 'Kalyan Silks', 'owner': {'name': 'Anjana'}, 'value': 'High', 'stuck_days': 1},
        ],
      }, 'quotes');

      expect(rows, hasLength(2));
      expect(rows[0].name, 'Workafella Coworking');
      expect(rows[0].sub, 'Deepak Raj');
      expect(rows[0].amt, '₹1.8Cr'); // parseable money → formatted
      expect(rows[0].age, '8 days ago');
      expect(rows[0].route, Routes.quoteDetail);
      expect(rows[0].id, 'q1');

      expect(rows[1].sub, 'Anjana');
      expect(rows[1].amt, 'High'); // non-money string passes through
      expect(rows[1].age, '1 day ago');
    });

    test('routes differ per chip; owner objects register into the directory', () {
      final pay = CrmHomeRemoteDataSource.mapStuck({
        'items': [
          {'id': 'p1', 'title': 'Marari Sands', 'owner': {'user_id': 'u9', 'full_name': 'Fariz Ahmed'}, 'value': 1830000, 'stuck_days': 15},
        ],
      }, 'pay');
      expect(pay[0].route, Routes.paymentDetail);
      expect(pay[0].amt, '₹18.3L');
      expect(MockUsers.byId['u9']?.name, 'Fariz Ahmed');

      final noproj = CrmHomeRemoteDataSource.mapStuck({'items': []}, 'noproj');
      expect(noproj, isEmpty);
    });
  });

  group('CRM home full bundle', () {
    test('an all-empty raw bundle maps to zeros/empties, never mock', () {
      final data = CrmHomeRemoteDataSource.mapHome(const {});
      expect(data.kpis, hasLength(4));
      expect(data.kpis.every((k) => k.value == '0'), isTrue);
      expect(data.firstResponseMedianMinutes, isNull);
      expect(data.funnel, isEmpty);
      expect(data.attention.every((a) => a.value == '0'), isTrue);
      expect(data.wins, isEmpty);
      expect(data.winsCount, 0);
      expect(data.winsTotal, 0);
      for (final key in const ['fu', 'pay', 'quotes', 'noproj']) {
        expect(data.overdue[key], isEmpty);
      }
    });
  });
}
