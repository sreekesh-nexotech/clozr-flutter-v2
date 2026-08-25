/// Server-computed figures behind the Helpdesk dashboard cards
/// (`admin_helpdesk_dashboard.md` §3, §9).
///
/// These used to be derived on the device from whatever page of tickets the
/// list happened to have loaded, so the numbers drifted from the server's and
/// silently under-counted anything past the first page.
library;

/// §3 `sla-priority-mix/` — the two donuts.
class SlaPriorityMix {
  const SlaPriorityMix({
    this.withinSla = 0,
    this.atRisk = 0,
    this.breached = 0,
    this.low = 0,
    this.medium = 0,
    this.high = 0,
    this.critical = 0,
  });

  final int withinSla;
  final int atRisk;
  final int breached;
  final int low;
  final int medium;
  final int high;
  final int critical;

  static SlaPriorityMix? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sla = raw['sla'];
    final pri = raw['priority'];
    return SlaPriorityMix(
      withinSla: _int(sla is Map ? sla['within_sla'] : null),
      atRisk: _int(sla is Map ? sla['at_risk'] : null),
      breached: _int(sla is Map ? sla['breached'] : null),
      low: _int(pri is Map ? pri['low'] : null),
      medium: _int(pri is Map ? pri['medium'] : null),
      high: _int(pri is Map ? pri['high'] : null),
      critical: _int(pri is Map ? pri['critical'] : null),
    );
  }
}

/// §9 `tickets-completed-grid/` — one row per priority.
class CompletedGridRow {
  const CompletedGridRow({
    required this.priority,
    this.beforeDue = 0,
    this.afterDue = 0,
  });

  final String priority;
  final int beforeDue;
  final int afterDue;

  static List<CompletedGridRow> listFrom(Object? raw) {
    if (raw is! Map || raw['rows'] is! List) return const [];
    final out = <CompletedGridRow>[];
    for (final r in raw['rows'] as List) {
      if (r is! Map) continue;
      final p = (r['priority'] ?? '').toString();
      if (p.isEmpty) continue;
      out.add(CompletedGridRow(
        priority: p,
        beforeDue: _int(r['before_due']),
        afterDue: _int(r['after_due']),
      ));
    }
    return out;
  }
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
