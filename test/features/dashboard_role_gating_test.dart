import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/features/auth/domain/entities/module_access.dart';
import 'package:clozrapp/features/shell/domain/nav_catalog.dart';
import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/dashboard/domain/entities/dashboard_models.dart';
import 'package:clozrapp/features/dashboard/infrastructure/data_sources/remote/dashboard_remote_ds.dart';

class _MockApi extends Mock implements ApiService {}

/// The dashboard asks only for the widget groups the role may read — a group it
/// cannot read is a 403 (it used to surface as a permission toast and an empty
/// Team picker).
void main() {
  late _MockApi api;
  late List<String> paths;
  late List<Map<String, dynamic>> queries;

  setUp(() {
    api = _MockApi();
    paths = [];
    queries = [];
    when(() => api.get(any(),
        query: any(named: 'query'),
        quiet: any(named: 'quiet'))).thenAnswer((i) async {
      paths.add(i.positionalArguments.first as String);
      final q = i.namedArguments[#query];
      if (q is Map) queries.add(Map<String, dynamic>.from(q));
      return <String, dynamic>{};
    });
  });

  test(
      'CRM-only dashboard role requests no Business, Operations or Helpdesk widgets',
      () async {
    await DashboardRemoteDataSource(api,
            includePmo: false,
            includeAdmin: false,
            includeCrm: true,
            includeIssue: false)
        .fetchSections();
    expect(paths, isNotEmpty);
    expect(paths.every((p) => p.contains('dashboard-crm')), isTrue,
        reason: '$paths');
  });

  test('a role without admin_dashboard never calls dashboard-new', () async {
    await DashboardRemoteDataSource(api,
            includePmo: true,
            includeAdmin: false,
            includeCrm: true,
            includeIssue: true)
        .fetchSections();
    expect(paths.where((p) => p.contains('dashboard-new')), isEmpty);
    expect(paths.where((p) => p.contains('dashboard-pmo')), isNotEmpty);
    expect(paths.where((p) => p.contains('dashboard-issue')), isNotEmpty);
  });

  test('a custom period sends the dates', () async {
    await DashboardRemoteDataSource(api,
            includePmo: false, includeAdmin: false, includeIssue: false)
        .fetchSections(period: 'custom', from: '2026-10-03', to: '2026-10-12');
    expect(queries, isNotEmpty);
    expect(
        queries.every((q) =>
            q['period'] == 'custom' &&
            q['from'] == '2026-10-03' &&
            q['to'] == '2026-10-12'),
        isTrue);
  });

  test('a preset period sends no dates', () async {
    await DashboardRemoteDataSource(api,
            includePmo: false, includeAdmin: false, includeIssue: false)
        .fetchSections(period: 'last_month');
    expect(queries.any((q) => q.containsKey('from') || q.containsKey('to')),
        isFalse);
  });

  test('one failing endpoint nulls only its own section', () async {
    when(() => api.get(any(that: contains('dashboard-pmo/kpis')),
            query: any(named: 'query'), quiet: any(named: 'quiet')))
        .thenThrow(const AppError(type: AppErrorType.server, message: 'boom'));
    final errors = <AppError>[];
    final sections =
        await DashboardRemoteDataSource(api).fetchSections(errors: errors);
    expect(sections[DashboardRemoteDataSource.kPmoKpis], isNull);
    expect(sections[DashboardRemoteDataSource.kCrmKpis], isNotNull);
    expect(sections[DashboardRemoteDataSource.kIssueKpis], isNotNull);
    expect(sections[DashboardRemoteDataSource.kCustomerKpis], isNotNull);
    expect(errors, hasLength(1));
  });

  test('stuck-item rows carry the record route for their kind', () {
    Map<String, Object?> items(String id) => {
          'items': [
            {
              'id': id,
              'title': 'Row',
              'owner': 'Me',
              'value': '100',
              'stuck_days': 3
            }
          ]
        };
    final d = DashboardRemoteDataSource.mapDashboard({
      DashboardRemoteDataSource.kCrmStuckLeads: items('l1'),
      DashboardRemoteDataSource.kCrmStuckQuotes: items('q1'),
      DashboardRemoteDataSource.kCrmStuckPayments: items('p1'),
      DashboardRemoteDataSource.kCrmStuckWonNc: items('w1'),
    }, DashboardData.empty());
    expect(d.crmStuck['stale']!.single.route, '/leads/detail?id=l1');
    expect(d.crmStuck['quotes']!.single.route, '/quotes/detail?id=q1');
    expect(d.crmStuck['payments']!.single.route, '/payments/detail?id=p1');
    expect(d.crmStuck['wonnc']!.single.route, '/leads/detail?id=w1');
  });

  test('the CRM New leads caption is not tied to a week', () {
    expect(DashboardData.empty().crmKpis.first.sub, 'This period, all sources');
  });

  test('team members narrow by team', () {
    const o = DashFilterOptions(
      [DashTeamOption('all', 'All teams', ''), DashTeamOption('t1', 'Dev', '')],
      [DashTeamOption('a', 'A', ''), DashTeamOption('b', 'B', '')],
      {
        't1': ['a']
      },
    );
    expect(o.membersOf('all').length, 2);
    expect(o.membersOf('t1').map((u) => u.id), ['a']);
  });

  test('a role with only crm_dashboard is offered the CRM tab alone', () {
    const crmOnly = ModuleAccess(modules: {
      'crm_dashboard': ModulePermission(label: 'CRM dashboard', canRead: true),
      'lead': ModulePermission(label: 'Lead', canRead: true),
    });
    expect(visibleDashboardTabs(crmOnly), ['crm']);
    const pmoToo = ModuleAccess(modules: {
      'crm_dashboard': ModulePermission(canRead: true),
      'pmo_dashboard': ModulePermission(canRead: true),
    });
    expect(visibleDashboardTabs(pmoToo), ['crm', 'ops']);
    expect(visibleDashboardTabs(const ModuleAccess()), isEmpty);
  });
}
