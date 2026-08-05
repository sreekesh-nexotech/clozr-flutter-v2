import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/app/router/routes.dart';
import 'package:clozrapp/features/dashboard/domain/entities/dashboard_models.dart';
import 'package:clozrapp/features/dashboard/infrastructure/data_sources/remote/dashboard_remote_ds.dart';

/// The audit fix: in API mode the mapper's base is [DashboardData.empty] — a
/// neutral, data-free bundle — so unsupplied sections stay honestly empty and
/// successful sections never inherit a mock sparkline/figure.
void main() {
  group('DashboardData.empty()', () {
    final empty = DashboardData.empty();

    test('KPI cards keep chrome but zero the data (no sparkline, no trend)', () {
      expect(empty.adminKpis, hasLength(4));
      final k = empty.adminKpis[0];
      expect(k.value, '0');
      expect(k.spark, isNull);
      expect(k.progress, isNull);
      expect(k.trend, '');
      // Design-token chrome is preserved.
      expect(k.route, Routes.leads);
      expect(k.label, 'Sales pipeline');
      // Fixed units survive so a mapped percentage still shows '%'.
      expect(empty.crmKpis[1].unit, '%');
      expect(empty.opsKpis[3].unit, 'days');
    });

    test('lists are empty and totals zeroed', () {
      expect(empty.crmFunnel, isEmpty);
      expect(empty.crmInflow.seriesA, isEmpty);
      expect(empty.crmSources, isEmpty);
      expect(empty.crmEmployees, isEmpty);
      expect(empty.aging, isEmpty);
      expect(empty.outstanding, isEmpty);
      expect(empty.receivablesTotal, '₹0');
      for (final key in const ['stale', 'quotes', 'payments', 'wonnc']) {
        expect(empty.crmStuck[key], isEmpty);
      }
      // The always-present "All teams" scope stays so the chip works.
      expect(empty.teamOptions, hasLength(1));
      expect(empty.teamOptions.first.id, 'all');
    });
  });

  group('mapDashboard over the empty base', () {
    final empty = DashboardData.empty();

    test('an unsupplied bundle stays empty — no mock leaks', () {
      final data = DashboardRemoteDataSource.mapDashboard(const {}, empty);
      expect(data.crmKpis[0].value, '0');
      expect(data.crmKpis[0].spark, isNull);
      expect(data.crmFunnel, isEmpty);
      expect(data.crmSources, isEmpty);
    });

    test('a supplied KPI carries real values but NO fabricated sparkline', () {
      final data = DashboardRemoteDataSource.mapDashboard({
        DashboardRemoteDataSource.kCrmKpis: {
          'new_leads': {'count': 142, 'trend_pct': 18.3},
        },
      }, empty);

      expect(data.crmKpis[0].value, '142');
      expect(data.crmKpis[0].trend, '+18.3%');
      expect(data.crmKpis[0].spark, isNull); // the leak this fix closes
      // A card the API didn't supply stays an honest zero (keeping its unit).
      expect(data.crmKpis[1].value, '0');
      expect(data.crmKpis[1].unit, '%');
    });
  });
}
