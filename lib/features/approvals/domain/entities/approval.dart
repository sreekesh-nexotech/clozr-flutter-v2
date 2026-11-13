import 'package:equatable/equatable.dart';

// Unified Approvals (`docs-flutter/APPROVALS_FLUTTER_ROUTEMAP.md`, backend
// contract `approvals.md`). Enum-like fields stay plain strings: the server
// may add values, and an unknown one must render rather than throw — the
// label maps in `approval_rules.dart` fall back for anything they don't know.

/// `kind` values.
abstract final class ApprovalKinds {
  static const close = 'close';
  static const ownerTransfer = 'owner_transfer';
  static const dueDate = 'due_date';
  static const all = [close, ownerTransfer, dueDate];
}

/// `status` values.
abstract final class ApprovalStatuses {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const withdrawn = 'withdrawn';
  static const superseded = 'superseded';
  static const all = [pending, approved, rejected, withdrawn, superseded];
}

/// `module` values — one per record type an approval can sit on.
abstract final class ApprovalModules {
  static const lead = 'lead';
  static const task = 'task';
  static const followup = 'followup';
  static const issue = 'issue';
  static const projectTask = 'project_task';
  static const project = 'project';
  static const all = [lead, task, followup, issue, projectTask, project];
}

/// The list's `tab` values.
abstract final class ApprovalTabs {
  static const pending = 'pending';
  static const mine = 'mine';
  static const team = 'team';
  static const history = 'history';
  static const all = [pending, mine, team, history];
}

/// The Team tab's `scope` values.
abstract final class ApprovalScopes {
  static const all = 'all';
  static const direct = 'direct';
  static const indirect = 'indirect';
  static const values = [all, direct, indirect];
}

String _s(Object? v) => v == null ? '' : '$v'.trim();

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

/// A person on a request (`{user_id, email, full_name}`).
class ApprovalUser extends Equatable {
  const ApprovalUser({required this.id, required this.name, this.email = ''});

  final String id;
  final String name;
  final String email;

  /// Null when the field is absent or carries nothing to show.
  static ApprovalUser? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = _s(m['user_id'] ?? m['id']);
    final email = _s(m['email']);
    final name = _s(m['full_name']).isNotEmpty ? _s(m['full_name']) : email;
    if (id.isEmpty && name.isEmpty) return null;
    return ApprovalUser(id: id, name: name, email: email);
  }

  @override
  List<Object?> get props => [id, name, email];
}

/// One row of `GET /approvals/`.
class Approval extends Equatable {
  const Approval({
    required this.id,
    required this.module,
    required this.kind,
    required this.objectId,
    required this.recordLabel,
    required this.status,
    this.projectId = '',
    this.canDecide = false,
    this.requestedBy,
    this.recordOwner,
    this.currentApprover,
    this.routeReason = '',
    this.from = '',
    this.to = '',
    this.requestNote = '',
    this.decisionSource = '',
    this.decidedBy,
    this.decidedAt,
    this.decisionNote = '',
    this.createdAt,
  });

  final String id;
  final String module;
  final String kind;

  /// The record's public UUID — what "Open record" links to.
  final String objectId;
  final String recordLabel;
  final String status;
  final String projectId;
  final bool canDecide;
  final ApprovalUser? requestedBy;
  final ApprovalUser? recordOwner;
  final ApprovalUser? currentApprover;
  final String routeReason;

  /// `display.from` / `display.to`, the labels snapshotted at request time.
  final String from;
  final String to;
  final String requestNote;

  /// Blank while pending, `user`, or `admin_override`.
  final String decisionSource;
  final ApprovalUser? decidedBy;
  final DateTime? decidedAt;
  final String decisionNote;
  final DateTime? createdAt;

  bool get isPending => status == ApprovalStatuses.pending;

  factory Approval.fromJson(Map<String, dynamic> m) {
    final display = _map(m['display']);
    return Approval(
      id: _s(m['approval_id'] ?? m['id']),
      module: _s(m['module']),
      kind: _s(m['kind']),
      objectId: _s(m['object_id']),
      recordLabel: _s(m['record_label']),
      status:
          _s(m['status']).isEmpty ? ApprovalStatuses.pending : _s(m['status']),
      projectId: _s(m['project_id']),
      canDecide: m['can_decide'] == true,
      requestedBy: ApprovalUser.fromJson(m['requested_by']),
      recordOwner: ApprovalUser.fromJson(m['record_owner']),
      currentApprover: ApprovalUser.fromJson(m['current_approver']),
      routeReason: _s(m['route_reason']),
      from: _s(display['from']),
      to: _s(display['to']),
      requestNote: _s(m['request_note']),
      decisionSource: _s(m['decision_source']),
      decidedBy: ApprovalUser.fromJson(m['decided_by']),
      decidedAt: DateTime.tryParse(_s(m['decided_at']))?.toLocal(),
      decisionNote: _s(m['decision_note']),
      createdAt: DateTime.tryParse(_s(m['created_at']))?.toLocal(),
    );
  }

  @override
  List<Object?> get props => [id, status, canDecide, currentApprover];
}

/// One routing step on a request.
class ApprovalStep extends Equatable {
  const ApprovalStep({
    required this.id,
    this.approver,
    this.reason = '',
    this.outcome = '',
    this.note = '',
    this.assignedAt,
    this.actedAt,
  });

  final String id;
  final ApprovalUser? approver;
  final String reason;

  /// Blank while open.
  final String outcome;
  final String note;
  final DateTime? assignedAt;
  final DateTime? actedAt;

  factory ApprovalStep.fromJson(Map<String, dynamic> m) => ApprovalStep(
        id: _s(m['step_id'] ?? m['id']),
        approver: ApprovalUser.fromJson(m['approver']),
        reason: _s(m['reason']),
        outcome: _s(m['outcome']),
        note: _s(m['note']),
        assignedAt: DateTime.tryParse(_s(m['assigned_at']))?.toLocal(),
        actedAt: DateTime.tryParse(_s(m['acted_at']))?.toLocal(),
      );

  @override
  List<Object?> get props => [id, outcome];
}

/// `GET /approvals/{id}/` — the row plus steps, the viewer's verbs and the
/// record summary (whose keys vary by module).
class ApprovalDetail extends Equatable {
  const ApprovalDetail({
    required this.approval,
    this.steps = const [],
    this.canEscalate = false,
    this.canWithdraw = false,
    this.summary = const [],
    this.recordVisible = false,
  });

  final Approval approval;
  final List<ApprovalStep> steps;
  final bool canEscalate;
  final bool canWithdraw;

  /// `record_summary` as ordered (key, value) pairs, blanks dropped.
  final List<(String, String)> summary;
  final bool recordVisible;

  factory ApprovalDetail.fromJson(Map<String, dynamic> m) {
    final rawSteps = m['steps'];
    return ApprovalDetail(
      approval: Approval.fromJson(m),
      steps: [
        if (rawSteps is List)
          for (final s in rawSteps)
            if (s is Map) ApprovalStep.fromJson(Map<String, dynamic>.from(s)),
      ],
      canEscalate: m['can_escalate'] == true,
      canWithdraw: m['can_withdraw'] == true,
      summary: [
        for (final e in _map(m['record_summary']).entries)
          if (e.value != null && e.value is! Map && e.value is! List)
            if (_s(e.value).isNotEmpty) (e.key, _s(e.value)),
      ],
      recordVisible: m['record_visible'] == true,
    );
  }

  @override
  List<Object?> get props => [approval, steps, canEscalate, canWithdraw];
}

/// One page of the list.
class ApprovalPage extends Equatable {
  const ApprovalPage({required this.count, required this.rows});

  static const empty = ApprovalPage(count: 0, rows: []);

  final int count;
  final List<Approval> rows;

  bool get hasMore => count > rows.length;

  @override
  List<Object?> get props => [count, rows];
}

/// The list's query. [page] is a 1-based page whose size is [pageSize]; the
/// screen grows [pageSize] for "show more" the way the other approval inboxes
/// on mobile do.
class ApprovalListQuery extends Equatable {
  const ApprovalListQuery({
    this.tab = ApprovalTabs.pending,
    this.kind,
    this.module,
    this.status,
    this.scope,
    this.requesterId,
    this.ownerId,
    this.projectId,
    this.createdAfter,
    this.createdBefore,
    this.search = '',
    this.page = 1,
    this.pageSize = 20,
  });

  final String tab;
  final String? kind;
  final String? module;
  final String? status;
  final String? scope;
  final String? requesterId;
  final String? ownerId;
  final String? projectId;

  /// Day bounds, sent as ISO date-times (start / end of the local day).
  final DateTime? createdAfter;
  final DateTime? createdBefore;
  final String search;
  final int page;
  final int pageSize;

  ApprovalListQuery copyWith({int? pageSize, int? page}) => ApprovalListQuery(
        tab: tab,
        kind: kind,
        module: module,
        status: status,
        scope: scope,
        requesterId: requesterId,
        ownerId: ownerId,
        projectId: projectId,
        createdAfter: createdAfter,
        createdBefore: createdBefore,
        search: search,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
      );

  @override
  List<Object?> get props => [
        tab,
        kind,
        module,
        status,
        scope,
        requesterId,
        ownerId,
        projectId,
        createdAfter,
        createdBefore,
        search,
        page,
        pageSize
      ];
}

/// `GET /approvals/counts/`.
class ApprovalCounts extends Equatable {
  const ApprovalCounts({
    this.pendingForMe = 0,
    this.byKind = const {},
    this.byModule = const {},
    this.other = const {},
  });

  static const zero = ApprovalCounts();

  final int pendingForMe;
  final Map<String, int> byKind;
  final Map<String, int> byModule;

  /// What waits on pages that keep their own flow: `quote_discounts`,
  /// `rewards`, `lifecycle`.
  final Map<String, int> other;

  static Map<String, int> _ints(Object? raw) => {
        for (final e in _map(raw).entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      };

  factory ApprovalCounts.fromJson(Object? raw) {
    final m = _map(raw);
    return ApprovalCounts(
      pendingForMe: (m['pending_for_me'] as num?)?.toInt() ?? 0,
      byKind: _ints(m['by_kind']),
      byModule: _ints(m['by_module']),
      other: _ints(m['other']),
    );
  }

  @override
  List<Object?> get props => [pendingForMe, byKind, byModule, other];
}

/// `pending_approval` on a record (detail read or `for-record`).
class PendingApproval extends Equatable {
  const PendingApproval({
    required this.id,
    this.kind = '',
    this.approverName = '',
    this.from = '',
    this.to = '',
    this.createdAt,
    this.canDecide = false,
    this.canEscalate = false,
    this.canWithdraw = false,
  });

  final String id;
  final String kind;
  final String approverName;
  final String from;
  final String to;
  final DateTime? createdAt;
  final bool canDecide;
  final bool canEscalate;
  final bool canWithdraw;

  static PendingApproval? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = _s(m['approval_id'] ?? m['id']);
    if (id.isEmpty) return null;
    if (_s(m['status']).isNotEmpty &&
        _s(m['status']) != ApprovalStatuses.pending) {
      return null;
    }
    final display = _map(m['display']);
    final approver = ApprovalUser.fromJson(m['current_approver']);
    return PendingApproval(
      id: id,
      kind: _s(m['kind']),
      approverName: approver?.name ?? '',
      from: _s(display['from']),
      to: _s(display['to']),
      createdAt: DateTime.tryParse(_s(m['created_at']))?.toLocal(),
      canDecide: m['can_decide'] == true,
      canEscalate: m['can_escalate'] == true,
      canWithdraw: m['can_withdraw'] == true,
    );
  }

  @override
  List<Object?> get props =>
      [id, kind, approverName, from, to, canDecide, canEscalate, canWithdraw];
}

/// `approval_gates` — for the current user: true means their save would wait
/// for approval (so ask for an optional comment first).
class ApprovalGates extends Equatable {
  const ApprovalGates(
      {this.close = false,
      this.ownerTransfer = false,
      this.closeStatuses = const []});

  static const none = ApprovalGates();

  final bool close;
  final bool ownerTransfer;

  /// Status *type* codes that count as closing (`won`, `completed`, …).
  final List<String> closeStatuses;

  factory ApprovalGates.fromJson(Object? raw) {
    final m = _map(raw);
    final statuses = m['close_statuses'];
    return ApprovalGates(
      close: m['close'] == true,
      ownerTransfer: m['owner_transfer'] == true,
      closeStatuses: [
        if (statuses is List)
          for (final s in statuses)
            if (_s(s).isNotEmpty) _s(s).toLowerCase(),
      ],
    );
  }

  @override
  List<Object?> get props => [close, ownerTransfer, closeStatuses];
}

/// A record's approval state: what waits on it, and what would.
class RecordApprovalState extends Equatable {
  const RecordApprovalState(
      {this.pending, this.gates = ApprovalGates.none, this.known = true});

  /// Nothing known — the state a failed check falls back to.
  static const unknown = RecordApprovalState(known: false);

  final PendingApproval? pending;
  final ApprovalGates gates;

  /// False when the record carried neither key (an older payload) — the
  /// caller should ask `for-record` instead.
  final bool known;

  /// From any map that may carry `pending_approval` / `approval_gates` — a
  /// record detail body or the `for-record` answer.
  factory RecordApprovalState.fromJson(Object? raw) {
    final m = _map(raw);
    final has =
        m.containsKey('pending_approval') || m.containsKey('approval_gates');
    return RecordApprovalState(
      pending: PendingApproval.fromJson(m['pending_approval']),
      gates: ApprovalGates.fromJson(m['approval_gates']),
      known: has,
    );
  }

  @override
  List<Object?> get props => [pending, gates, known];
}

/// One row the server could not decide in a bulk call.
class BulkDecisionError extends Equatable {
  const BulkDecisionError(
      {required this.id, required this.code, required this.message});

  final String id;
  final String code;
  final String message;

  @override
  List<Object?> get props => [id, code, message];
}

/// `POST /approvals/bulk-decide/`.
class BulkDecisionResult extends Equatable {
  const BulkDecisionResult(
      {required this.updated,
      this.skippedIds = const [],
      this.errors = const []});

  final int updated;
  final List<String> skippedIds;
  final List<BulkDecisionError> errors;

  factory BulkDecisionResult.fromJson(Object? raw) {
    final m = _map(raw);
    final skipped = m['skipped_ids'];
    final errors = m['errors'];
    return BulkDecisionResult(
      updated: (m['updated'] as num?)?.toInt() ?? 0,
      skippedIds: [
        if (skipped is List)
          for (final s in skipped) _s(s)
      ],
      errors: [
        if (errors is List)
          for (final e in errors)
            if (e is Map)
              BulkDecisionError(
                  id: _s(e['id']),
                  code: _s(e['code']),
                  message: _s(e['message'] ?? e['detail'])),
      ],
    );
  }

  @override
  List<Object?> get props => [updated, skippedIds, errors];
}
