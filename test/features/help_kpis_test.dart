// The Helpdesk home's KPI cards carried prototype constants — "3.2 days",
// "1.4 hours" and four trend chips that never moved. These cover the figures
// that replaced them. Fixture is the live `/crm/dashboard-issue/kpis/` shape.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/helpdesk/domain/entities/help_kpis.dart';

void main() {
  group('the live payload maps onto the cards', () {
    final kpis = HelpKpis.fromJson({
      'open_tickets': {'count': 7, 'trend_pct': 8.0},
      'sla_breaches': {'count': 2, 'trend_pct': -8.4},
      'avg_resolution': {'minutes': 4608, 'trend_pct': -8.4},
      'first_response': {'minutes': 84, 'trend_pct': 3.9},
      'reopen_rate': {'pct': 12.5, 'trend_pct': 0.0},
    })!;

    test('durations convert into each card’s own unit', () {
      // Both arrive in minutes; the cards read days and hours.
      expect(kpis.avgResolution!.days, 3.2);
      expect(kpis.firstResponse!.hours, 1.4);
    });

    test('the chip shows magnitude; direction is the arrow', () {
      expect(kpis.openTickets!.trendLabel, '8%'); // whole → no decimal
      expect(kpis.openTickets!.trendUp, isTrue);
      expect(kpis.slaBreaches!.trendLabel, '8.4%'); // no double minus
      expect(kpis.slaBreaches!.trendUp, isFalse);
    });

    test('counts and rates come through', () {
      expect(kpis.openTickets!.count, 7);
      expect(kpis.reopenRate!.pct, 12.5);
    });
  });

  group('a missing figure shows nothing rather than a zero', () {
    test('no trend_pct means no chip', () {
      final k = HelpKpi.fromJson({'count': 3})!;

      expect(k.hasTrend, isFalse);
      expect(k.trendLabel, isEmpty);
      // No duration → the card renders a dash, not "0 days".
      expect(k.days, isNull);
      expect(k.hours, isNull);
    });

    test('a 403 or junk body maps to null', () {
      // The route sits behind the dashboard permission; the screen must keep
      // rendering its locally-derived counts.
      expect(HelpKpis.fromJson(null), isNull);
      expect(HelpKpis.fromJson('forbidden'), isNull);
      expect(HelpKpis.fromJson({'detail': 'no permission'}), isNull);
    });

    test('a partial payload keeps what it did send', () {
      final partial = HelpKpis.fromJson({'open_tickets': {'count': 1}})!;

      expect(partial.openTickets!.count, 1);
      expect(partial.avgResolution, isNull);
    });
  });
}
