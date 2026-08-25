// The Operations home KPI cards carried prototype constants — a "2.3%" chip on
// every build and a 4.5-day cycle time nothing measured. These cover the figures
// that replaced them. Fixture is the shape in
// `docs-flutter/docs-backend/admin_operations_dashboard.md` §1.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/operations/domain/entities/ops_kpis.dart';
import 'package:clozrapp/features/operations/domain/entities/ops_task.dart';
import 'package:clozrapp/features/operations/infrastructure/data_sources/remote/ops_tasks_remote_ds.dart';

final _body = {
  'active_projects': {'count': 6, 'trend_pct': 2.3},
  'projects_overdue': {'count': 3, 'total': 11, 'trend_pct': -2.0},
  'tasks_overdue': {'count': 7, 'trend_pct': -8.4},
  'avg_project_cycle': {'days': 48.0, 'trend_pct': 2.4},
  'avg_task_cycle': {'days': 3.2, 'trend_pct': -8.4},
};

void main() {
  group('the documented payload maps onto the cards', () {
    final kpis = OpsKpis.fromJson(_body)!;

    test('counts, ratios and durations all come through', () {
      expect(kpis.activeProjects!.count, 6);
      // The "3 / 11" ratio needs both halves.
      expect(kpis.projectsOverdue!.count, 3);
      expect(kpis.projectsOverdue!.total, 11);
      expect(kpis.tasksOverdue!.count, 7);
      expect(kpis.avgTaskCycle!.days, 3.2);
    });

    test('the trend chip shows magnitude; direction is the arrow', () {
      expect(kpis.activeProjects!.trendLabel, '2.3%');
      expect(kpis.activeProjects!.trendUp, isTrue);
      // Negative keeps its magnitude — the minus is not printed twice.
      expect(kpis.tasksOverdue!.trendLabel, '8.4%');
      expect(kpis.tasksOverdue!.trendUp, isFalse);
    });

    test('a whole percentage drops its decimal', () {
      final whole = OpsKpi.fromJson({'count': 1, 'trend_pct': 5.0})!;

      expect(whole.trendLabel, '5%');
    });

    test('string numbers are tolerated', () {
      final asStrings = OpsKpi.fromJson({'count': '4', 'trend_pct': '1.5'})!;

      expect(asStrings.count, 4);
      expect(asStrings.trendPct, 1.5);
    });
  });

  group('a missing figure shows no chip rather than a flat one', () {
    test('no trend_pct means no trend', () {
      final noTrend = OpsKpi.fromJson({'count': 2})!;

      expect(noTrend.hasTrend, isFalse);
      expect(noTrend.trendLabel, isEmpty);
    });

    test('a 403 or junk body maps to null, not to zeros', () {
      // The route sits behind `view_dashboard`; without it the screen has to
      // fall back to the counts it derives itself.
      expect(OpsKpis.fromJson(null), isNull);
      expect(OpsKpis.fromJson('forbidden'), isNull);
      expect(OpsKpis.fromJson({'detail': 'no permission'}), isNull);
    });

    test('a partial payload keeps what it did send', () {
      final partial = OpsKpis.fromJson({'active_projects': {'count': 2}})!;

      expect(partial.activeProjects!.count, 2);
      expect(partial.avgTaskCycle, isNull);
    });
  });

  // Verified against the dev backend, which answers with all four priorities —
  // the card used to hard-code three, so "Urgent" had nowhere to land.
  group('the completed-tasks grid', () {
    test('maps the live rows, priorities included', () {
      final rows = OpsCompletedRow.listFromJson({
        'rows': [
          {'priority': 'Urgent', 'before_due': 2, 'after_due': 1},
          {'priority': 'High', 'before_due': 0, 'after_due': 0},
          {'priority': 'Medium', 'before_due': 5, 'after_due': 0},
          {'priority': 'Low', 'before_due': 0, 'after_due': 3},
        ],
      });

      expect([for (final r in rows) r.priority],
          ['Urgent', 'High', 'Medium', 'Low']);
      expect(rows.first.beforeDue, 2);
      expect(rows.first.afterDue, 1);
      expect(rows.last.afterDue, 3);
    });

    test('a junk or forbidden body yields no rows, not zeroed ones', () {
      expect(OpsCompletedRow.listFromJson({'detail': 'nope'}), isEmpty);
      expect(OpsCompletedRow.listFromJson(null), isEmpty);
      // A row with no priority has no home on the card.
      expect(
          OpsCompletedRow.listFromJson({
            'rows': [
              {'before_due': 1, 'after_due': 0},
            ],
          }),
          isEmpty);
    });
  });

  group('a task carries when it was actually finished', () {
    OpsTask mapped(Map<String, dynamic> extra) =>
        OpsTasksRemoteDataSource.mapOpsTask({
          'task_id': 't1',
          'subject': 'Fit-out',
          'exp_end_date': '2026-07-10T12:30:00Z',
          'priority': 'High',
          ...extra,
        })!;

    test('act_end_date is read, and completed_on backs it up', () {
      // Neither was mapped before, so the detail page's "Actual: … completed …"
      // read "—" for every finished task in the org.
      expect(mapped({'act_end_date': '2026-07-08T09:00:00Z'}).actualEndISO,
          '2026-07-08T09:00:00Z');
      expect(mapped({'completed_on': '2026-07-08T09:00:00Z'}).actualEndISO,
          '2026-07-08T09:00:00Z');
      // The explicit date wins over the status stamp.
      expect(
          mapped({
            'act_end_date': '2026-07-08T09:00:00Z',
            'completed_on': '2026-07-09T09:00:00Z',
          }).actualEndISO,
          '2026-07-08T09:00:00Z');
    });

    test('early, late and unknown are told apart', () {
      expect(mapped({'act_end_date': '2026-07-08T09:00:00Z'}).completedLate,
          isFalse);
      expect(mapped({'act_end_date': '2026-07-12T09:00:00Z'}).completedLate,
          isTrue);
      // Finished on the due date itself is not late, whatever the clock says.
      expect(mapped({'act_end_date': '2026-07-10T23:00:00Z'}).completedLate,
          isFalse);
      // Never finished → not known, which is not the same as on time.
      expect(mapped(const {}).completedLate, isNull);
    });
  });
}
