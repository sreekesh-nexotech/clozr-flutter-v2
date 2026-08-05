import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/data/mock/mock_users.dart';
import 'package:clozrapp/features/dashboard/domain/entities/dash_colors.dart';
import 'package:clozrapp/features/dashboard/domain/entities/dashboard_models.dart';
import 'package:clozrapp/features/dashboard/infrastructure/data_sources/local/dashboard_mock_ds.dart';
import 'package:clozrapp/features/dashboard/infrastructure/data_sources/remote/dashboard_remote_ds.dart';

void main() {
  final base = const DashboardMockDataSource().load();

  DashboardData map(Map<String, Object?> raw) =>
      DashboardRemoteDataSource.mapDashboard(raw, base);

  tearDown(UserDirectory.reset);

  group('admin KPI cards', () {
    test('maps money/count values, signed trends and mock chrome reuse', () {
      final data = map({
        DashboardRemoteDataSource.kCustomerKpis: {
          'sales_pipeline': {'amount': '1840000.00', 'trend_pct': 12.3},
          'payments_collected': {
            'collected': '940000.00',
            'expected': '2220000.00',
            'trend_pct': 12.3
          },
          'overdue_receivables': {
            'amount': '440000.00',
            'customer_count': 23,
            'trend_pct': 14.0
          },
          'open_tickets': {'count': 147, 'trend_pct': -8.0},
        },
      });

      final pipeline = data.adminKpis[0];
      expect(pipeline.value, '₹18.4');
      expect(pipeline.unit, 'L');
      expect(pipeline.trend, '+12.3%');
      expect(pipeline.trendPositive, isTrue);
      expect(pipeline.arrow, DashTrendArrow.up);
      // Icon/accent/route are reused from the mock card at the same position.
      expect(pipeline.icon, base.adminKpis[0].icon);
      expect(pipeline.accent, base.adminKpis[0].accent);
      expect(pipeline.route, base.adminKpis[0].route);

      expect(data.adminKpis[1].value, '₹9.4');
      expect(data.adminKpis[1].sub, 'Of ₹22.2L expected');

      final overdue = data.adminKpis[2];
      expect(overdue.value, '₹4.4');
      expect(overdue.sub, 'Across 23 customers');
      expect(overdue.trend, '+14%');
      expect(overdue.trendPositive, isFalse); // overdue up = bad
      expect(overdue.arrow, DashTrendArrow.up);

      final tickets = data.adminKpis[3];
      expect(tickets.value, '147');
      expect(tickets.trend, '-8%');
      expect(tickets.trendPositive, isTrue); // fewer tickets = good
      expect(tickets.arrow, DashTrendArrow.down);
    });
  });

  group('total receivables', () {
    test('maps totals, disjoint aging and cumulative upcoming buckets', () {
      final data = map({
        DashboardRemoteDataSource.kReceivables: {
          'total_amount': '10500000.00',
          'overdue': {
            'total_amount': '5440000.00',
            '0_30': {'amount': '1820000.00', 'count': 12},
            '31_60': {'amount': '1240000.00', 'count': 8},
            '61_90': {'amount': '1360000.00', 'count': 6},
            '90_plus': {'amount': '1020000.00', 'count': 4},
          },
          'upcoming': {
            'total_amount': '5060000.00',
            'today': {'amount': '640000.00', 'count': 3},
            'next_7': {'amount': '1210000.00', 'count': 5},
            // Cumulative buckets: next_30 ⊇ next_7, next_90 ⊇ next_30.
            'next_30': {'amount': '1850000.00', 'count': 9},
            'next_90': {'amount': '1360000.00', 'count': 4},
          },
        },
      });

      expect(data.receivablesTotal, '₹1.1Cr');
      expect(data.receivablesSub, '₹54.4L overdue · ₹50.6L upcoming');
      expect(data.overdueTotal, 'Overdue · ₹54.4L');
      expect(data.upcomingTotal, 'Upcoming · ₹50.6L');

      expect(data.aging, hasLength(4));
      expect(data.aging[0].label, '0–30 days');
      expect(data.aging[0].amt, '₹18.2L');
      expect(data.aging[0].color, base.aging[0].color); // mock color by index
      expect(data.aging[0].pct, closeTo(33.46, 0.05)); // 18.2L of 54.4L
      expect(data.aging[3].label, '90+ days');
      expect(data.aging[3].amt, '₹10.2L');

      // The cumulative amounts render as sent, one row per bucket.
      expect(data.upcoming, hasLength(4));
      expect(data.upcoming[0].label, 'Due today');
      expect(data.upcoming[0].amt, '₹6.4L');
      expect(data.upcoming[2].label, 'Due in 30 days');
      expect(data.upcoming[2].amt, '₹18.5L');
      expect(data.upcoming[3].amt, '₹13.6L');
    });

    test('zero overdue total guards the aging percentage division', () {
      final data = map({
        DashboardRemoteDataSource.kReceivables: {
          'total_amount': '0.00',
          'overdue': {
            'total_amount': '0.00',
            '0_30': {'amount': '0.00', 'count': 0},
            '31_60': {'amount': '0.00', 'count': 0},
            '61_90': {'amount': '0.00', 'count': 0},
            '90_plus': {'amount': '0.00', 'count': 0},
          },
          'upcoming': {'total_amount': '0.00'},
        },
      });
      expect(data.aging.every((a) => a.pct == 0), isTrue);
      // Upcoming map had no bucket rows → mock rows kept.
      expect(data.upcoming, base.upcoming);
    });
  });

  group('top customers / outstanding', () {
    test('maps both lists with relative bars and a summed total', () {
      final data = map({
        DashboardRemoteDataSource.kTopCustomers: {
          'top_outstanding': [
            {
              'customer_id': 'c1',
              'name': 'Kalyan Silks',
              'outstanding_amount': '1220000.00',
              'oldest_overdue_days': 112
            },
            {
              'customer_id': 'c2',
              'name': 'Bismi Hypermarket',
              'outstanding_amount': '610000.00',
              'oldest_overdue_days': 91
            },
          ],
          'top_by_value': [
            {
              'customer_id': 'c3',
              'name': 'Nirapara Supermarket',
              'total_value': '22200000.00',
              'outstanding_amount': '0.00'
            },
          ],
        },
      });

      expect(data.outstanding, hasLength(2));
      expect(data.outstanding[0].name, 'Kalyan Silks');
      expect(data.outstanding[0].days, 112);
      expect(data.outstanding[0].amt, '₹12.2L');
      expect(data.outstanding[0].pct, 100); // largest row
      expect(data.outstanding[0].barColor, base.outstanding[0].barColor);
      expect(data.outstanding[1].pct, closeTo(50, 0.01));
      expect(data.outstandingTotal, '₹18.3L'); // 12.2L + 6.1L

      expect(data.topCustomers, hasLength(1));
      expect(data.topCustomers[0].name, 'Nirapara Supermarket');
      expect(data.topCustomers[0].sub, '—');
      expect(data.topCustomers[0].amt, '₹2.2Cr');
    });
  });

  group('stuck items', () {
    test('formats money values, passes priority names through, keys the tabs', () {
      final data = map({
        DashboardRemoteDataSource.kCrmStuckLeads: {
          'kind': 'leads',
          'items': [
            {
              'id': 'l1',
              'title': 'Toms Auto Hyundai',
              'owner': 'Vinod Kumar',
              'value': '9500000.00',
              'stuck_days': 14
            },
          ],
        },
        DashboardRemoteDataSource.kCrmStuckQuotes: {
          'kind': 'quotes',
          'items': [
            {
              'id': 'q1',
              'title': 'Lulu Fashion Store',
              'owner': 'Rahul Krishnan',
              'value': 'High', // polymorphic: priority name, not money
              'stuck_days': 8
            },
          ],
        },
      });

      final stale = data.crmStuck['stale']!;
      expect(stale, hasLength(1));
      expect(stale[0].name, 'Toms Auto Hyundai');
      expect(stale[0].sub, 'Vinod Kumar');
      expect(stale[0].amt, '₹95L'); // parseable money string → formatted
      expect(stale[0].age, '14d');

      expect(data.crmStuck['quotes']![0].amt, 'High'); // raw string kept

      // Kinds whose calls failed fall back to the mock rows untouched.
      expect(identical(data.crmStuck['payments'], base.crmStuck['payments']), isTrue);
      expect(identical(data.crmStuck['wonnc'], base.crmStuck['wonnc']), isTrue);
    });
  });

  group('lead sources', () {
    test('maps rows with win pct, em-dash cycle and formatted won amount', () {
      final data = map({
        DashboardRemoteDataSource.kCrmSources: {
          'sources': [
            {
              'id': 's1',
              'name': 'Website',
              'total_leads': 8,
              'won_leads': 3,
              'lost_leads': 2,
              'win_pct': 38.0,
              'won_amount': '46400000.00',
              'pipeline_amount': '23593.00'
            },
          ],
        },
      });
      expect(data.crmSources, hasLength(1));
      final source = data.crmSources[0];
      expect(source.name, 'Website');
      expect(source.leads, 8);
      expect(source.won, 3);
      expect(source.pct, '38%');
      expect(source.cycle, '—'); // no cycle metric in the API
      expect(source.closed, '₹4.6Cr');
      expect(source.up, isNull);
    });
  });

  group('attention needed', () {
    test('renders direction labels and signed deltas, keeps unmapped cards', () {
      final data = map({
        DashboardRemoteDataSource.kCrmMissed: {
          'payments_missed': {'count': 12, 'trend_pct': 3.0, 'direction': 'worsening'},
          'followups_missed': {'count': 28, 'trend_pct': 0.0, 'direction': 'steady'},
          'tasks_missed': {'count': 19, 'trend_pct': -5.0, 'direction': 'improving'},
          // lost_after_quote absent → mock card kept.
        },
      });
      expect(data.crmAttention[0].value, '12');
      expect(data.crmAttention[0].delta, '+3%');
      expect(data.crmAttention[0].note, 'Worsening');
      expect(data.crmAttention[0].noteColor, DashColors.red);
      expect(data.crmAttention[0].positive, isFalse);

      expect(data.crmAttention[1].delta, '0');
      expect(data.crmAttention[1].neutral, isTrue);
      expect(data.crmAttention[1].note, 'Steady');

      expect(data.crmAttention[2].delta, '-5%');
      expect(data.crmAttention[2].positive, isTrue);
      expect(data.crmAttention[2].note, 'Improving');
      expect(data.crmAttention[2].arrow, DashTrendArrow.down);

      expect(identical(data.crmAttention[3], base.crmAttention[3]), isTrue);
    });
  });

  group('lead funnel and inflow trend', () {
    test('maps stages to bars and buckets to a two-series trend', () {
      final data = map({
        DashboardRemoteDataSource.kCrmFunnel: {
          'crm': {
            'stages': [
              {'lead_status_id': 'a', 'name': 'New', 'position': 1, 'count': 4},
              {'lead_status_id': 'b', 'name': 'Negotiation', 'position': 2, 'count': 7},
              {'lead_status_id': 'c', 'name': 'Waiting for approval', 'position': 3, 'count': 2},
            ],
            'total': 13,
          },
        },
        DashboardRemoteDataSource.kCrmInflow: {
          'buckets': [
            for (final m in ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'])
              {'label': '$m 2026', 'new_leads': 10, 'won_leads': 4},
          ],
        },
      });

      expect(data.crmFunnel, hasLength(3));
      expect(data.crmFunnel[0].label, 'New');
      expect(data.crmFunnel[1].label, 'Negotiation'); // ≤12 chars stays whole
      expect(data.crmFunnel[2].label, 'Waiting'); // long name → first word
      expect(data.crmFunnel[1].count, 7);

      expect(data.crmInflow.seriesA, hasLength(6));
      expect(data.crmInflow.seriesA[0], 10);
      expect(data.crmInflow.seriesB[0], 4);
      expect(data.crmInflow.min, 0);
      expect(data.crmInflow.max, greaterThanOrEqualTo(10));
      expect(data.crmInflow.axisLabels, hasLength(4));
      expect(data.crmInflow.axisLabels.first, 'Jan');
      expect(data.crmInflow.axisLabels.last, 'Jun');
    });
  });

  group('employee performance', () {
    test('maps the signed-in uuid to "me" and registers names', () {
      UserDirectory.currentUserId = 'uuid-me';
      final data = map({
        DashboardRemoteDataSource.kCrmEmployees: {
          'count': 2,
          'next': null,
          'results': [
            {
              'user_id': 'uuid-me',
              'name': 'Sreekesh Nath',
              'open_leads': 3,
              'won_leads': 1,
              'closed_amount': '1240000.00',
              'first_response_median_minutes': 21,
              'last_active_at':
                  DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
            },
            {
              'user_id': 'uuid-2',
              'name': 'Anjana M.',
              'open_leads': 1,
              'won_leads': 4,
              'closed_amount': '1240000.00',
              'first_response_median_minutes': 18,
              'last_active_at': '2026-07-29T10:00:00Z',
            },
          ],
        },
      });

      expect(data.crmEmployees, hasLength(2));
      expect(data.crmEmployees[0].rid, 'me');
      expect(data.crmEmployees[1].rid, 'uuid-2');
      expect(data.crmEmployees[0].active, 3);
      expect(data.crmEmployees[0].closed, '₹12.4L');
      expect(data.crmEmployees[0].ftr, '21 min');
      expect(data.crmEmployees[0].last, '5m ago');
      expect(MockUsers.byId['uuid-2']?.name, 'Anjana M.');
    });
  });

  group('operations', () {
    test('active projects: health drives the panel tab, hex colors parse', () {
      final data = map({
        DashboardRemoteDataSource.kPmoProjects: {
          'count': 3,
          'results': [
            {
              'project_id': 'p1',
              'name': 'Showroom Fit-out',
              'manager': {'id': 'm1', 'name': 'Manoj Varma'},
              'status': {'id': 's1', 'name': 'Overdue', 'color': '#E71111'},
              'progress_pct': 85,
              'days_remaining': -5,
              'value': '4200000.00',
              'health': 'delayed',
            },
            {
              'project_id': 'p2',
              'name': 'Banquet Hall',
              'manager': {'name': 'Anjana Menon'},
              'status': {'name': 'At risk', 'color': '#EDA032'},
              'progress_pct': 30,
              'days_remaining': 4,
              'value': '1000000.00',
              'health': 'at_risk',
            },
            {
              'project_id': 'p3',
              'name': 'Spa Joinery',
              'manager': {'name': 'Rahul'},
              'status': {'name': 'On track', 'color': 'bogus'},
              'progress_pct': 50,
              'days_remaining': 10,
              'value': '500000.00',
              'health': 'on_track',
            },
          ],
        },
      });

      expect(data.opsProjects, hasLength(3));
      final delayed = data.opsProjects[0];
      expect(delayed.name, 'Showroom Fit-out');
      expect(delayed.owner, 'Manoj Varma');
      expect(delayed.value, '₹42L');
      expect(delayed.statusLabel, 'Overdue');
      expect(delayed.statusColor, const Color(0xFFE71111)); // '#RRGGBB' parsed
      expect(delayed.progress, 85);
      expect(delayed.days, -5);
      // The ops panel shows 'active' rows in All active + (days<0) Overdue,
      // and 'onhold' rows under At risk — health maps onto that vocabulary.
      expect(delayed.tab, 'active');
      expect(data.opsProjects[1].tab, 'onhold'); // at_risk
      expect(data.opsProjects[2].tab, 'active'); // on_track
      // Unparseable hex falls back to the health color.
      expect(data.opsProjects[2].statusColor, DashColors.green);
    });

    test('project status donut parses hex colors and counts', () {
      final data = map({
        DashboardRemoteDataSource.kPmoStatus: {
          'total': 9,
          'statuses': [
            {'status_id': 'a', 'name': 'Complete', 'color': '#890DB6', 'is_closed': true, 'count': 4},
            {'status_id': 'b', 'name': 'On track', 'color': '#0E8F3D', 'is_closed': false, 'count': 5},
          ],
        },
      });
      expect(data.opsStatus, hasLength(2));
      expect(data.opsStatus[0].label, 'Complete');
      expect(data.opsStatus[0].color, const Color(0xFF890DB6));
      expect(data.opsStatus[0].count, 4);
      expect(data.opsStatus[1].color, const Color(0xFF0E8F3D));
    });

    test('overdue tasks map title, project sub/value and overdue label', () {
      final data = map({
        DashboardRemoteDataSource.kPmoOverdue: {
          'tasks': [
            {
              'task_id': 't1',
              'title': 'Install false ceiling grid',
              'days_overdue': 18,
              'assigned_to': {'id': 'u9', 'name': 'Manoj Varma'},
              'customer': {'id': 'c9', 'name': 'Kalyan Silks'},
              'project': {'id': 'p9', 'name': 'Showroom Fit-out', 'value': '4200000.00'},
            },
          ],
        },
      });
      expect(data.opsOverdue, hasLength(1));
      expect(data.opsOverdue[0].title, 'Install false ceiling grid');
      expect(data.opsOverdue[0].sub, 'Showroom Fit-out');
      expect(data.opsOverdue[0].value, '₹42L');
      expect(data.opsOverdue[0].overdue, '18d overdue');
    });
  });

  group('teams and helpdesk', () {
    test('team options come straight from the API items', () {
      final data = map({
        DashboardRemoteDataSource.kTeams: {
          'has_teams': true,
          'items': [
            {'label': 'All team', 'value': 'all'},
            {'label': 'Sales North', 'value': 'team-uuid-1'},
            {'label': 'Individual', 'value': 'individual'},
          ],
        },
      });
      expect(data.teamOptions, hasLength(3));
      expect(data.teamOptions[0].id, 'all');
      expect(data.teamOptions[1].id, 'team-uuid-1');
      expect(data.teamOptions[1].name, 'Sales North');
      expect(data.teamOptions[1].sub, '');
    });

    test('undocumented issue KPIs map per-card and keep mock for the rest', () {
      final data = map({
        DashboardRemoteDataSource.kIssueKpis: {
          'open_tickets': {'count': 20, 'trend_pct': -8.0},
        },
      });
      expect(data.helpKpis[0].value, '20');
      expect(data.helpKpis[0].trend, '-8%');
      expect(data.helpKpis[0].trendPositive, isTrue); // fewer open = good
      expect(identical(data.helpKpis[1], base.helpKpis[1]), isTrue);
      expect(identical(data.helpKpis[2], base.helpKpis[2]), isTrue);
    });

    test('issue KPIs map the documented payload, minutes → hours for resolution', () {
      final data = map({
        DashboardRemoteDataSource.kIssueKpis: {
          'open_tickets': {'count': 17, 'trend_pct': -5.0},
          'sla_breaches': {'count': 3, 'trend_pct': 50.0},
          'avg_resolution': {'minutes': 412, 'trend_pct': -8.2},
          'first_response': {'minutes': 95, 'trend_pct': 12.0},
          'reopen_rate': {'pct': 4.8, 'trend_pct': 1.5}, // no slot in the 4-card grid
        },
      });
      expect(data.helpKpis[0].value, '17');
      expect(data.helpKpis[1].value, '3');
      expect(data.helpKpis[1].trendPositive, isFalse); // more breaches = bad
      expect(data.helpKpis[2].value, '6.9'); // 412 min → 6.87 h → 6.9
      expect(data.helpKpis[2].unit, 'hours'); // card reads in hours, API in minutes
      expect(data.helpKpis[2].trendPositive, isTrue); // resolving faster = good
      expect(data.helpKpis[3].value, '95'); // already minutes, no conversion
    });

    test('legacy hours keys for avg resolution pass through unconverted', () {
      final data = map({
        DashboardRemoteDataSource.kIssueKpis: {
          'avg_resolution': {'hours': 7, 'trend_pct': 0},
        },
      });
      expect(data.helpKpis[2].value, '7');
    });

    test('SLA/priority mix reads the flat count blocks, not a row list', () {
      final data = map({
        DashboardRemoteDataSource.kIssueSla: {
          'sla': {'within_sla': 25, 'at_risk': 4, 'breached': 3},
          'priority': {'low': 8, 'medium': 14, 'high': 7, 'critical': 3},
        },
      });
      expect(data.helpSla, hasLength(3));
      expect(data.helpSla[0].label, 'Within SLA');
      expect(data.helpSla[0].count, 25);
      expect(data.helpSla[0].color, DashColors.green);
      expect(data.helpSla[1].label, 'At Risk');
      expect(data.helpSla[2].label, 'Breached');
      expect(data.helpSla[2].count, 3);
      expect(data.helpSla[2].color, DashColors.red);

      expect(data.helpPriority, hasLength(4));
      expect(data.helpPriority[1].label, 'Medium');
      expect(data.helpPriority[1].count, 14);
      expect(data.helpPriority[3].label, 'Critical');
      expect(data.helpPriority[3].color, DashColors.red);
    });

    test('all-zero SLA blocks still map — an empty helpdesk is not a failure', () {
      final data = map({
        DashboardRemoteDataSource.kIssueSla: {
          'sla': {'within_sla': 0, 'at_risk': 0, 'breached': 0},
          'priority': {'low': 0, 'medium': 0, 'high': 0, 'critical': 0},
        },
      });
      expect(data.helpSla, hasLength(3));
      expect(data.helpPriority, hasLength(4));
      expect(data.helpSla.map((p) => p.count), everyElement(0));
    });

    test('an omitted SLA block falls back to its base donut', () {
      final data = map({
        DashboardRemoteDataSource.kIssueSla: {
          'priority': {'low': 1, 'medium': 0, 'high': 0, 'critical': 0},
        },
      });
      expect(identical(data.helpSla, base.helpSla), isTrue);
      expect(data.helpPriority[0].count, 1);
    });
  });

  group('full fallback', () {
    test('an all-failed bundle returns the mock sections untouched', () {
      final data = DashboardRemoteDataSource.mapDashboard(<String, Object?>{}, base);

      expect(identical(data.adminKpis, base.adminKpis), isTrue);
      expect(data.receivablesTotal, base.receivablesTotal);
      expect(data.receivablesSub, base.receivablesSub);
      expect(data.overdueTotal, base.overdueTotal);
      expect(data.upcomingTotal, base.upcomingTotal);
      expect(identical(data.aging, base.aging), isTrue);
      expect(identical(data.upcoming, base.upcoming), isTrue);
      expect(identical(data.outstanding, base.outstanding), isTrue);
      expect(data.outstandingTotal, base.outstandingTotal);
      expect(identical(data.topCustomers, base.topCustomers), isTrue);
      expect(identical(data.crmKpis, base.crmKpis), isTrue);
      expect(identical(data.crmFunnel, base.crmFunnel), isTrue);
      expect(identical(data.crmInflow, base.crmInflow), isTrue);
      expect(identical(data.crmAttention, base.crmAttention), isTrue);
      expect(identical(data.crmSources, base.crmSources), isTrue);
      for (final key in const ['stale', 'quotes', 'payments', 'wonnc']) {
        expect(identical(data.crmStuck[key], base.crmStuck[key]), isTrue);
      }
      expect(identical(data.crmEmployees, base.crmEmployees), isTrue);
      expect(identical(data.opsKpis, base.opsKpis), isTrue);
      expect(identical(data.opsStatus, base.opsStatus), isTrue);
      expect(identical(data.opsOverdue, base.opsOverdue), isTrue);
      expect(identical(data.opsProjects, base.opsProjects), isTrue);
      expect(identical(data.opsRoster, base.opsRoster), isTrue);
      expect(identical(data.helpKpis, base.helpKpis), isTrue);
      expect(identical(data.helpCategories, base.helpCategories), isTrue);
      expect(identical(data.helpSla, base.helpSla), isTrue);
      expect(identical(data.helpPriority, base.helpPriority), isTrue);
      expect(identical(data.helpAttention, base.helpAttention), isTrue);
      expect(identical(data.helpFlow, base.helpFlow), isTrue);
      expect(identical(data.helpRoster, base.helpRoster), isTrue);
      expect(identical(data.teamOptions, base.teamOptions), isTrue);
    });
  });
}
