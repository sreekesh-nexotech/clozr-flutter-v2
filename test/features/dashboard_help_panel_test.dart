import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/auth/domain/entities/module_access.dart';
import 'package:clozrapp/features/dashboard/application/providers/dashboard_providers.dart';
import 'package:clozrapp/features/dashboard/domain/entities/dashboard_models.dart';
import 'package:clozrapp/features/dashboard/infrastructure/data_sources/remote/dashboard_remote_ds.dart';
import 'package:clozrapp/features/dashboard/presentation/components/panels/help_panel.dart';
import 'package:clozrapp/features/shell/domain/nav_catalog.dart';

/// Helpdesk tab: trend colours, roster counts, empty attention list, tab gating.
void main() {
  DashboardData mapped(Map<String, Object?> raw) =>
      DashboardRemoteDataSource.mapDashboard(raw, DashboardData.empty());

  test('rising open tickets / breaches are red, falling are green', () {
    final up = mapped({
      DashboardRemoteDataSource.kIssueKpis: {
        'open_tickets': {'count': 10, 'trend_pct': 25.0},
        'sla_breaches': {'count': 4, 'trend_pct': 50.0},
        'avg_resolution': {'minutes': 120, 'trend_pct': 10.0},
        'first_response': {'minutes': 15, 'trend_pct': 8.0},
      },
    });
    expect(up.helpKpis.every((k) => !k.trendPositive), isTrue);
    expect(up.helpKpis[0].arrow, DashTrendArrow.up);
    final down = mapped({
      DashboardRemoteDataSource.kIssueKpis: {
        'open_tickets': {'count': 3, 'trend_pct': -25.0},
        'sla_breaches': {'count': 0, 'trend_pct': -100.0},
        'avg_resolution': {'minutes': 30, 'trend_pct': -10.0},
        'first_response': {'minutes': 5, 'trend_pct': -8.0},
      },
    });
    expect(down.helpKpis.every((k) => k.trendPositive), isTrue);
    expect(down.helpKpis[1].arrow, DashTrendArrow.down);
  });

  test('medians the server could not measure read "—", not 0', () {
    final d = mapped({
      DashboardRemoteDataSource.kIssueKpis: {
        'open_tickets': {'count': 4, 'trend_pct': null},
        'sla_breaches': {'count': 0, 'trend_pct': null},
        'avg_resolution': {'minutes': null, 'trend_pct': null},
        'first_response': {'minutes': null, 'trend_pct': null},
      },
      DashboardRemoteDataSource.kCrmKpis: {
        'new_leads': {'count': 7, 'trend_pct': -84.4},
        'first_response': {'median_minutes': null, 'trend_pct': null},
      },
    });
    expect(d.helpKpis[0].value, '4');
    expect(d.helpKpis[2].value, '—');
    expect(d.helpKpis[2].unit, '');
    expect(d.helpKpis[3].value, '—');
    expect(d.crmKpis[2].value, '—');
    expect(d.crmKpis[2].unit, '');
  });

  test('lead inflow maps the server buckets and names the calendar year', () {
    final d = mapped({
      DashboardRemoteDataSource.kCrmInflow: {
        'buckets': [
          for (var m = 1; m <= 12; m++)
            {
              'label': '${const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1]} 2026',
              'new_leads': m == 10 ? 47 : (m == 11 ? 8 : 0),
              'won_leads': m == 10 ? 12 : (m == 11 ? 7 : 0),
            }
        ]
      },
    });
    expect(d.crmInflow.seriesA.length, 12);
    expect(d.crmInflow.seriesA[9], 47); // Oct created
    expect(d.crmInflow.seriesB[10], 7); // Nov converted
    expect(d.crmInflow.year, '2026');
    expect(d.crmInflow.axisLabels.first, 'Jan');
  });

  test('roster reads assigned_issues / resolved_issues', () {
    final d = mapped({
      DashboardRemoteDataSource.kIssueEmployees: {
        'results': [
          {
            'user_id': 'u1',
            'name': 'Sneha',
            'assigned_issues': 3,
            'resolved_issues': 1,
            'sla_breaches': 2
          },
          {
            'user_id': 'u2',
            'name': 'Arun',
            'assigned_issues': 0,
            'resolved_issues': 0,
            'sla_breaches': 0
          },
        ]
      },
    });
    expect(d.helpRoster[0].sub, '3 open · 1 resolved');
    expect(d.helpRoster[0].chipLabel, '2 breaches');
    expect(d.helpRoster[0].chipBad, isTrue);
    expect(d.helpRoster[1].sub, '0 open · 0 resolved');
    expect(d.helpRoster[1].chipBad, isFalse);
  });

  test('Helpdesk tab needs issue_dashboard', () {
    const noHelp = ModuleAccess(modules: {
      'crm_dashboard': ModulePermission(canRead: true),
    });
    expect(visibleDashboardTabs(noHelp).contains('help'), isFalse);
    const help = ModuleAccess(modules: {
      'issue_dashboard': ModulePermission(canRead: true),
    });
    expect(visibleDashboardTabs(help), ['help']);
  });

  testWidgets('no tickets needing attention shows the empty state',
      (tester) async {
    tester.view.physicalSize = const Size(780, 4200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dashboardDataProvider.overrideWithValue(DashboardData.empty())
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: HelpPanel()))),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Nothing needs attention'), findsOneWidget);
  });
}
