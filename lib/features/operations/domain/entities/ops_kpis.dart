import 'package:equatable/equatable.dart';

/// One KPI figure: a live count (or a duration in days) and the period-over-
/// period trend that drives the card's chip.
///
/// [trendPct] is null when the server did not send one, which the card reads as
/// "show no chip" — a missing trend is not a flat one.
class OpsKpi extends Equatable {
  const OpsKpi({this.count, this.days, this.total, this.trendPct});

  final int? count;
  final double? days;

  /// The denominator on the ratio cards (`projects_overdue` sends "3 / 11").
  final int? total;
  final double? trendPct;

  bool get hasTrend => trendPct != null;

  /// Trend chips read "2.3%" — the sign is carried by the arrow and the colour.
  String get trendLabel {
    final pct = trendPct;
    if (pct == null) return '';
    final abs = pct.abs();
    final text = abs == abs.roundToDouble()
        ? abs.round().toString()
        : abs.toStringAsFixed(1);
    return '$text%';
  }

  bool get trendUp => (trendPct ?? 0) >= 0;

  static OpsKpi? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return OpsKpi(
      count: _int(raw['count']),
      days: _double(raw['days']),
      total: _int(raw['total']),
      trendPct: _double(raw['trend_pct']),
    );
  }

  @override
  List<Object?> get props => [count, days, total, trendPct];
}

/// `GET /crm/dashboard-pmo/kpis/` — the figures behind the Operations home KPI
/// grid (`admin_operations_dashboard.md` §1).
///
/// Every field is nullable: the endpoint sits behind `view_dashboard` and
/// answers 403 without it, so the screen has to work with none of this. What it
/// supplies that the screen cannot compute for itself is the **trend** on each
/// card and the **avg task cycle**, which needs completion timestamps the task
/// list does not carry.
class OpsKpis extends Equatable {
  const OpsKpis({
    this.activeProjects,
    this.projectsOverdue,
    this.tasksOverdue,
    this.avgProjectCycle,
    this.avgTaskCycle,
  });

  final OpsKpi? activeProjects;
  final OpsKpi? projectsOverdue;
  final OpsKpi? tasksOverdue;
  final OpsKpi? avgProjectCycle;
  final OpsKpi? avgTaskCycle;

  static OpsKpis? fromJson(Object? body) {
    if (body is! Map) return null;
    final kpis = OpsKpis(
      activeProjects: OpsKpi.fromJson(body['active_projects']),
      projectsOverdue: OpsKpi.fromJson(body['projects_overdue']),
      tasksOverdue: OpsKpi.fromJson(body['tasks_overdue']),
      avgProjectCycle: OpsKpi.fromJson(body['avg_project_cycle']),
      avgTaskCycle: OpsKpi.fromJson(body['avg_task_cycle']),
    );
    // A 200 that carried none of the documented keys is not a usable payload.
    return kpis.props.any((p) => p != null) ? kpis : null;
  }

  @override
  List<Object?> get props =>
      [activeProjects, projectsOverdue, tasksOverdue, avgProjectCycle, avgTaskCycle];
}

/// One row of the completed-tasks grid: a priority, and how many tasks at that
/// priority were finished before vs after their due date.
///
/// `GET /crm/dashboard-pmo/tasks-completed-grid/` →
/// `{"rows":[{"priority":"Urgent","before_due":0,"after_due":0}, …]}`.
/// The server names the priorities, so an org using "Urgent" gets a row for it
/// rather than the three the screen used to hard-code.
class OpsCompletedRow extends Equatable {
  const OpsCompletedRow({
    required this.priority,
    required this.beforeDue,
    required this.afterDue,
  });

  final String priority;
  final int beforeDue;
  final int afterDue;

  static List<OpsCompletedRow> listFromJson(Object? body) {
    final rows = body is Map ? body['rows'] : body;
    if (rows is! List) return const [];
    final out = <OpsCompletedRow>[];
    for (final r in rows) {
      if (r is! Map) continue;
      final priority = (r['priority'] ?? '').toString().trim();
      if (priority.isEmpty) continue;
      out.add(OpsCompletedRow(
        priority: priority,
        beforeDue: _int(r['before_due']) ?? 0,
        afterDue: _int(r['after_due']) ?? 0,
      ));
    }
    return out;
  }

  @override
  List<Object?> get props => [priority, beforeDue, afterDue];
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double? _double(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}
