/// A write that the server accepted but held for approval (Unified
/// Approvals, `docs-flutter/APPROVALS_FLUTTER_ROUTEMAP.md` Phase 3).
///
/// Lives in `core/network` because [ApiService] reads it off every response —
/// the mobile twin of the webapp's response interceptor (`approvalHold.ts`) —
/// so no write path can forget to tell the user that its change is waiting.
library;

/// The 202 body code that marks a held save.
const approvalRequiredCode = 'APPROVAL_REQUIRED';

const _holdStatus = 202;
const _sentFallback = 'Sent for approval.';

/// One held save, or the record ids of a bulk / due-date write that went for
/// approval.
class ApprovalHold {
  const ApprovalHold({
    this.approvalId = '',
    this.objectId = '',
    this.message = _sentFallback,
    this.approverName = '',
    this.from = '',
    this.to = '',
    this.appliedFields = const [],
    this.pendingIds = const [],
  });

  final String approvalId;

  /// The record the request sits on (its public UUID).
  final String objectId;

  /// The server's sentence ("Sent to Priya Nair for approval.").
  final String message;
  final String approverName;
  final String from;
  final String to;

  /// The parts of the save that did apply.
  final List<String> appliedFields;

  /// Bulk status writes and due-date moves carry no envelope — just the ids
  /// that went for approval. Empty on a single held save.
  final List<String> pendingIds;

  /// Whether this is a single held save (vs. a list of pending ids).
  bool get isEnvelope => approvalId.isNotEmpty;

  /// Every record id this event marks as waiting.
  List<String> get heldIds => [
        if (objectId.isNotEmpty) objectId,
        for (final id in pendingIds)
          if (id.isNotEmpty && id != objectId) id,
      ];
}

String _s(Object? v) => v == null ? '' : '$v'.trim();

/// The held save in a response, or null for every other answer. A due-date
/// 202 is not one — it has no envelope (see [readPendingIds]).
ApprovalHold? readApprovalHold(int status, Object? body) {
  if (status != _holdStatus || body is! Map) return null;
  if (body['code'] != approvalRequiredCode) return null;
  final approval = body['approval'];
  if (approval is! Map) return null;
  final id = _s(approval['approval_id']);
  if (id.isEmpty) return null;
  final approver = approval['current_approver'];
  final display = approval['display'];
  final applied = body['applied_fields'];
  final detail = _s(body['detail']);
  return ApprovalHold(
    approvalId: id,
    objectId: _s(approval['object_id']),
    message: detail.isEmpty ? _sentFallback : detail,
    approverName: approver is Map ? _s(approver['full_name']) : '',
    from: display is Map ? _s(display['from']) : '',
    to: display is Map ? _s(display['to']) : '',
    appliedFields: [
      if (applied is List)
        for (final f in applied) _s(f)
    ],
  );
}

/// The record body of a write: the envelope's `record` on a held save, else
/// the body itself — so a caller that maps the answer as the record keeps
/// working when its save was held.
Object? recordOf(int status, Object? body) {
  if (status != _holdStatus || body is! Map) return body;
  if (body['code'] != approvalRequiredCode) return body;
  final record = body['record'];
  return record is Map ? record : body;
}

/// The record ids a bulk or due-date 202 sent for approval: a bulk status
/// answers `pending_ids`, a due-date PATCH the record plus its pending change.
List<String> readPendingIds(int status, Object? body) {
  if (status != _holdStatus || body is! Map) return const [];
  final ids = body['pending_ids'];
  if (ids is List) {
    return [
      for (final id in ids)
        if (_s(id).isNotEmpty) _s(id)
    ];
  }
  final change = body['pending_due_date_change'];
  final objectId = change is Map ? _s(change['object_id']) : '';
  return objectId.isEmpty ? const [] : [objectId];
}

/// Everything a 202 tells the app, or null when it is not about approval.
ApprovalHold? approvalEventOf(int status, Object? body) {
  final hold = readApprovalHold(status, body);
  if (hold != null) return hold;
  final ids = readPendingIds(status, body);
  return ids.isEmpty ? null : ApprovalHold(pendingIds: ids, message: '');
}
