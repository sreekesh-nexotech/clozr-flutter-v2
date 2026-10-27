import 'package:equatable/equatable.dart';

/// `GET /crm/issues/summary/` — the Support Overview figures (helpdesk.md §7).
///
/// Worth reading from the server rather than counting the loaded tickets: the
/// SLA arithmetic runs against a **pause-aware** effective deadline
/// (`sla_deadline` + accumulated hold time + any hold in flight), so a ticket
/// parked on hold does not drift toward "breached" while it is frozen. The
/// client has no way to reproduce that from a list row.
///
/// The four SLA buckets count **open tickets only** and are mutually exclusive,
/// so they sum to the open total.
/// One card in an SLA-watch bucket or the workload list (helpdesk.md §7).
///
/// `slaRemainingSeconds` is **signed and pause-aware** — negative means already
/// breached, and time parked on hold has been subtracted server-side. That is
/// the one figure a client cannot derive from a list row.
class SummaryCard extends Equatable {
  const SummaryCard({
    required this.id,
    this.reference = '',
    this.subject = '',
    this.priority = 'Medium',
    this.assigneeId = '',
    this.assigneeName = '',
    this.statusName = '',
    this.slaRemainingSeconds,
    this.slaPaused = false,
    this.hasLinkedTasks = false,
    this.createdAt,
  });

  final String id;
  final String reference;
  final String subject;
  final String priority;
  final String assigneeId;
  final String assigneeName;
  final String statusName;
  final int? slaRemainingSeconds;

  /// The SLA clock is stopped (`sla_hold_started_at` set) — the card's pill
  /// reads "Paused".
  final bool slaPaused;

  /// The ticket has a linked Operations task (the card's link glyph).
  final bool hasLinkedTasks;

  /// When the ticket was raised — the Pipeline card's age ("3d").
  final DateTime? createdAt;

  /// The effective deadline as an instant, so the existing SLA pills and
  /// buckets can read it the way they read any other due date.
  DateTime? get dueAt => slaRemainingSeconds == null
      ? null
      : DateTime.now().add(Duration(seconds: slaRemainingSeconds!));

  static SummaryCard? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = (raw['issue_id'] ?? '').toString();
    if (id.isEmpty) return null;
    final assignee = raw['assignee'];
    return SummaryCard(
      id: id,
      reference: (raw['reference'] ?? '').toString(),
      subject: (raw['subject'] ?? '').toString(),
      priority: (raw['priority'] ?? 'Medium').toString(),
      assigneeId: assignee is Map
          ? (assignee['user_id'] ?? assignee['id'] ?? '').toString()
          : (raw['assigned_to'] ?? '').toString(),
      assigneeName: assignee is Map
          ? (assignee['name'] ?? '').toString()
          : (raw['assigned_to_name'] ?? '').toString(),
      statusName: (raw['status_name'] ?? '').toString(),
      slaRemainingSeconds: _int(raw['sla_remaining_seconds']),
      slaPaused: (raw['sla_hold_started_at'] ?? '').toString().isNotEmpty,
      hasLinkedTasks: raw['has_linked_tasks'] == true,
      createdAt: DateTime.tryParse((raw['created_at'] ?? '').toString()),
    );
  }

  @override
  List<Object?> get props => [id, slaRemainingSeconds];
}

/// One SLA-watch bucket: an uncapped [total] with at most 8 [items], so the UI
/// renders "showing 8 of 23" rather than claiming 8 is the whole set.
class SlaBucket extends Equatable {
  const SlaBucket({this.total = 0, this.items = const []});

  final int total;
  final List<SummaryCard> items;

  static SlaBucket fromJson(Object? raw) {
    if (raw is! Map) return const SlaBucket();
    return SlaBucket(
      total: _int(raw['total']) ?? 0,
      items: [
        for (final row in raw['items'] as List? ?? const [])
          if (SummaryCard.fromJson(row) case final c?) c,
      ],
    );
  }

  @override
  List<Object?> get props => [total, items];
}

/// One Workload column: [agentId] / [agentName] empty for the Unassigned
/// column, which always comes first.
class WorkloadColumn extends Equatable {
  const WorkloadColumn({this.agentId = '', this.agentName = '', this.total = 0, this.items = const []});

  final String agentId;
  final String agentName;
  final int total;
  final List<SummaryCard> items;

  bool get isUnassigned => agentId.isEmpty && agentName.isEmpty;

  @override
  List<Object?> get props => [agentId, agentName, total, items];
}

/// One Pipeline lane — one per org status, ordered by `position`.
class PipelineLane extends Equatable {
  const PipelineLane({required this.id, required this.name, this.color, this.position = 0, this.total = 0, this.items = const []});

  final String id;
  final String name;

  /// The status' own colour (`#3B82F6`), null when unset.
  final String? color;
  final int position;
  final int total;
  final List<SummaryCard> items;

  @override
  List<Object?> get props => [id, name, position, total, items];
}

/// A `(name, total)` pair — one agent's load, or one status column.
class NamedTotal extends Equatable {
  const NamedTotal(this.name, this.total, {this.id = ''});

  final String id;
  final String name;
  final int total;

  @override
  List<Object?> get props => [id, name, total];
}

class IssueSummary extends Equatable {
  const IssueSummary({
    this.open = 0,
    this.breachedNow = 0,
    this.dueToday = 0,
    this.closedToday = 0,
    this.slaBreached = 0,
    this.slaDueWithin = 0,
    this.slaDueToday = 0,
    this.slaOnTrack = 0,
    this.resolvedTotal = 0,
    this.breached = const SlaBucket(),
    this.dueWithin = const SlaBucket(),
    this.dueTodayBucket = const SlaBucket(),
    this.onTrack = const SlaBucket(),
    this.unassigned = const SlaBucket(),
    this.byAgent = const [],
    this.pipeline = const [],
    this.noSla,
    this.workload = const [],
    this.lanes = const [],
  });

  // stats
  final int open;
  final int breachedNow;
  final int dueToday;
  final int closedToday;

  // sla_watch bucket totals (uncapped — `items` is capped at 8)
  final int slaBreached;
  final int slaDueWithin;
  final int slaDueToday;
  final int slaOnTrack;

  /// Tickets sitting in a status the org marks resolved, summed from
  /// `pipeline` — the SLA buckets exclude them, but the "Within SLA" slice
  /// counts work that finished inside its target.
  final int resolvedTotal;

  /// The four SLA-watch buckets, each with its capped card list.
  final SlaBucket breached;
  final SlaBucket dueWithin;
  final SlaBucket dueTodayBucket;
  final SlaBucket onTrack;

  /// `workload.unassigned` — open tickets nobody is on.
  final SlaBucket unassigned;

  /// `workload.by_agent` — open tickets per assignee, server-ordered.
  final List<NamedTotal> byAgent;

  /// `pipeline` — totals per status, keyed by the org's own `IssueStatus` rows
  /// rather than a fixed column set.
  final List<NamedTotal> pipeline;

  /// Open tickets with no SLA deadline, when the server reports the bucket
  /// (a bucket, a bare count, or `stats.no_sla`); null otherwise.
  final SlaBucket? noSla;

  /// Unassigned first, then each agent — with their cards when sent.
  final List<WorkloadColumn> workload;

  /// The Pipeline lanes in `position` order, with their cards when sent.
  final List<PipelineLane> lanes;

  /// Not breached and not due within the hour: on track, due later today, and
  /// everything already resolved.
  int get withinSla => slaOnTrack + slaDueToday + resolvedTotal;

  static IssueSummary? fromJson(Object? body) {
    if (body is! Map) return null;
    final stats = body['stats'];
    final watch = body['sla_watch'];
    if (stats is! Map && watch is! Map) return null;

    int bucket(String name) {
      final b = watch is Map ? watch[name] : null;
      return b is Map ? (_int(b['total']) ?? 0) : 0;
    }

    SlaBucket watchBucket(String name) =>
        SlaBucket.fromJson(watch is Map ? watch[name] : null);

    var resolved = 0;
    final pipelineRows = <NamedTotal>[];
    final pipeline = body['pipeline'];
    if (pipeline is List) {
      for (final row in pipeline) {
        if (row is! Map) continue;
        final total = _int(row['total']) ?? 0;
        if (row['is_resolved'] == true) resolved += total;
        final name = (row['name'] ?? '').toString();
        if (name.isEmpty) continue;
        pipelineRows.add(NamedTotal(name, total,
            id: (row['issue_status_id'] ?? '').toString()));
      }
    }

    final lanes = <PipelineLane>[
      if (pipeline is List)
        for (final row in pipeline)
          if (row is Map && (row['name'] ?? '').toString().isNotEmpty)
            PipelineLane(
              id: (row['issue_status_id'] ?? '').toString(),
              name: (row['name'] ?? '').toString(),
              color: row['color'] is String ? row['color'] as String : null,
              position: _int(row['position']) ?? 0,
              total: _int(row['total']) ?? 0,
              items: SlaBucket.fromJson(row).items,
            ),
    ]..sort((a, b) => a.position.compareTo(b.position));

    final rawNoSla = watch is Map ? watch['no_sla'] : null;
    final statNoSla = stats is Map ? _int(stats['no_sla']) : null;
    final noSla = rawNoSla is Map
        ? SlaBucket.fromJson(rawNoSla)
        : (_int(rawNoSla) ?? statNoSla) != null
            ? SlaBucket(total: (_int(rawNoSla) ?? statNoSla)!)
            : null;

    final workload = body['workload'];
    final columns = <WorkloadColumn>[
      WorkloadColumn(
        total: workload is Map && workload['unassigned'] is Map ? _int((workload['unassigned'] as Map)['total']) ?? 0 : 0,
        items: SlaBucket.fromJson(workload is Map ? workload['unassigned'] : null).items,
      ),
      if (workload is Map && workload['by_agent'] is List)
        for (final row in workload['by_agent'] as List)
          if (row is Map)
            WorkloadColumn(
              agentId: row['user'] is Map ? ((row['user'] as Map)['user_id'] ?? (row['user'] as Map)['id'] ?? '').toString() : '',
              agentName: row['user'] is Map ? ((row['user'] as Map)['name'] ?? '').toString() : '',
              total: _int(row['total']) ?? 0,
              items: SlaBucket.fromJson(row).items,
            ),
    ];
    final agents = <NamedTotal>[];
    if (workload is Map && workload['by_agent'] is List) {
      for (final row in workload['by_agent'] as List) {
        if (row is! Map) continue;
        final user = row['user'];
        final name = user is Map ? (user['name'] ?? '').toString() : '';
        if (name.isEmpty) continue;
        agents.add(NamedTotal(name, _int(row['total']) ?? 0,
            id: user is Map ? (user['user_id'] ?? '').toString() : ''));
      }
    }

    return IssueSummary(
      open: stats is Map ? _int(stats['open']) ?? 0 : 0,
      breachedNow: stats is Map ? _int(stats['breached_now']) ?? 0 : 0,
      dueToday: stats is Map ? _int(stats['due_today']) ?? 0 : 0,
      closedToday: stats is Map ? _int(stats['closed_today']) ?? 0 : 0,
      slaBreached: bucket('breached'),
      slaDueWithin: bucket('due_within'),
      slaDueToday: bucket('due_today'),
      slaOnTrack: bucket('on_track'),
      resolvedTotal: resolved,
      breached: watchBucket('breached'),
      dueWithin: watchBucket('due_within'),
      dueTodayBucket: watchBucket('due_today'),
      onTrack: watchBucket('on_track'),
      unassigned: SlaBucket.fromJson(
          workload is Map ? workload['unassigned'] : null),
      byAgent: agents,
      pipeline: pipelineRows,
      noSla: noSla,
      workload: columns,
      lanes: lanes,
    );
  }

  @override
  List<Object?> get props => [
        open,
        breachedNow,
        dueToday,
        closedToday,
        slaBreached,
        slaDueWithin,
        slaDueToday,
        slaOnTrack,
        resolvedTotal,
        breached,
        dueWithin,
        dueTodayBucket,
        onTrack,
        unassigned,
        byAgent,
        pipeline,
        noSla,
        workload,
        lanes,
      ];
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}
