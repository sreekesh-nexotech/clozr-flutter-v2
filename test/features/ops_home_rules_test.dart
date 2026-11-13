import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/operations/infrastructure/data_sources/remote/ops_dashboard_remote_ds.dart';

import 'package:clozrapp/features/operations/domain/entities/ops_kpis.dart';
import 'package:clozrapp/features/operations/domain/entities/ops_task.dart';
import 'package:clozrapp/features/operations/presentation/screens/ops_home_screen.dart';

OpsTask _t(String id, String pri, String endISO) => OpsTask(
      id: id,
      subject: id,
      projId: 'p',
      group: '',
      status: 'open',
      pri: pri,
      assignees: const ['me'],
      milestone: false,
      start: '',
      startTime: '',
      end: endISO,
      endTime: '',
      endISO: endISO,
      progress: 0,
      dept: '',
      color: const OpsColorTag('t', Color(0xFF000000)),
      subtasks: const [],
      waitingOn: const [],
      notes: const [],
      desc: '',
    );

void main() {
  final tasks = [
    _t('nodate-high', 'High', ''),
    _t('low-soon', 'Low', '2026-11-05'),
    _t('urgent-late', 'Urgent', '2026-11-20'),
    _t('med-early', 'Medium', '2026-11-02'),
    _t('high-mid', 'High', '2026-11-10'),
    _t('unknown', 'Whatever', '2026-11-01'),
  ];

  test(
      'My Tasks › Priority: Urgent, High, Medium, Low, unknown last; no date last within a priority',
      () {
    expect(OpsHomeScreen.sortMyTasks(tasks, 'priority').map((t) => t.id), [
      'urgent-late',
      'high-mid',
      'nodate-high',
      'med-early',
      'low-soon',
      'unknown',
    ]);
  });

  test('My Tasks › Due: closest first, tasks with no end date last', () {
    expect(OpsHomeScreen.sortMyTasks(tasks, 'due').map((t) => t.id), [
      'unknown',
      'med-early',
      'low-soon',
      'high-mid',
      'urgent-late',
      'nodate-high',
    ]);
  });

  test('Top attention: five closest due dates, overdue first, no-date last',
      () {
    final top = OpsHomeScreen.topAttention(tasks).map((t) => t.id).toList();
    expect(
        top, ['unknown', 'med-early', 'low-soon', 'high-mid', 'urgent-late']);
    expect(top.contains('nodate-high'), isFalse);
    expect(OpsHomeScreen.topAttention(const []), isEmpty);
  });

  test('a trend chip is shown only beside the count the server measured', () {
    const k = OpsKpi(count: 29, trendPct: -100);
    expect(OpsHomeScreen.trendFor(k, 29), same(k));
    expect(
        OpsHomeScreen.trendFor(k, 1), isNull); // card shows a different count
    expect(
        OpsHomeScreen.trendFor(const OpsKpi(count: 1), 1), isNull); // no trend
    expect(OpsHomeScreen.trendFor(null, 1), isNull);
  });

  test('server KPI payload keeps its trend and total', () {
    final kpis = OpsKpis.fromJson({
      'active_projects': {'count': 4, 'trend_pct': 12.5},
      'projects_overdue': {'count': 1, 'total': 4},
      'tasks_overdue': {'count': 3, 'trend_pct': -50},
    })!;
    expect(kpis.activeProjects!.trendLabel, '12.5%');
    expect(kpis.activeProjects!.trendUp, isTrue);
    expect(kpis.tasksOverdue!.trendUp, isFalse);
    expect(kpis.projectsOverdue!.total, 4);
    expect(OpsKpis.fromJson({'unrelated': 1}), isNull);
  });

  test('KPI and grid failures degrade to nothing (never throw)', () async {
    final api = _MockApi();
    when(() => api.get(any(), query: any(named: 'query'))).thenThrow(
        const AppError(
            type: AppErrorType.forbidden, message: 'No view_dashboard'));
    final ds = OpsDashboardRemoteDataSource(api);
    expect(await ds.fetchKpis(), isNull);
    expect(await ds.fetchCompletedGrid(), isEmpty);
  });

  test('a custom period sends from / to; a preset does not', () async {
    final api = _MockApi();
    final queries = <Map<String, dynamic>>[];
    when(() => api.get(any(), query: any(named: 'query')))
        .thenAnswer((i) async {
      queries.add(Map<String, dynamic>.from(i.namedArguments[#query] as Map));
      return <String, dynamic>{};
    });
    final ds = OpsDashboardRemoteDataSource(api);
    await ds.fetchKpis(period: 'custom', from: '2026-10-03', to: '2026-10-12');
    await ds.fetchCompletedGrid(period: 'last_month');
    expect(queries[0]['from'], '2026-10-03');
    expect(queries[0]['to'], '2026-10-12');
    expect(queries[1]['period'], 'last_month');
    expect(queries[1].containsKey('from'), isFalse);
  });
}

class _MockApi extends Mock implements ApiService {}
