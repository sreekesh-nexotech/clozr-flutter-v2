/// Maps server status vocabularies (org-editable names + fixed `status_type`
/// codes) onto the fixed UI status keys in `StatusMeta$`.
///
/// Strategy everywhere: match the org-specific *name* first (it is what the
/// admin actually renamed), then fall back to the fixed `status_type`, then a
/// safe default — so an org's custom "Won Deal" still lands in the right
/// bucket via its type.
library;

String _norm(String? s) => (s ?? '').toLowerCase().trim();

/// Lead → `new | qualified | quote | negotiation | won | lost | archived`.
///
/// [type] is the org's `status_type` (`new | in_progress | won | lost | junk`).
/// For the three **terminal** types it is authoritative and checked *before*
/// the name, because a name match would otherwise win incorrectly — the real
/// case being "Disqualified" (`junk`), whose name contains `qualif` and used to
/// land in the Qualified bucket. `in_progress` says nothing about *which*
/// stage, so for it the name still decides (Negotiation vs Qualified vs Quote).
String leadStatusKey({String? name, String? type}) {
  final n = _norm(name);
  final t = _norm(type);

  // Terminal types: authoritative, name cannot override.
  switch (t) {
    case 'won':
      return 'won';
    case 'lost':
      return 'lost';
    case 'junk':
      return 'archived';
  }

  // Name matching for the stages `status_type` cannot distinguish. The junk
  // names are tested first so "Disqualified" never trips the `qualif` check.
  if (n.contains('junk') ||
      n.contains('spam') ||
      n.contains('archiv') ||
      n.contains('disqualif')) {
    return 'archived';
  }
  if (n.contains('qualif')) return 'qualified';
  if (n.contains('quote') || n.contains('proposal')) return 'quote';
  if (n.contains('negoti')) return 'negotiation';
  if (n.contains('won')) return 'won';
  if (n.contains('lost')) return 'lost';
  if (n.contains('new')) return 'new';
  return t == 'in_progress' ? 'qualified' : 'new';
}

/// Customer → `active | upsell | completed | lost`.
String customerStatusKey({String? name, String? type}) {
  switch (_norm(type)) {
    case 'active':
      return 'active';
    case 'upsell_in_progress':
      return 'upsell';
    case 'completed':
      return 'completed';
    case 'lost':
      return 'lost';
  }
  final n = _norm(name);
  if (n.contains('upsell')) return 'upsell';
  if (n.contains('complete')) return 'completed';
  if (n.contains('lost')) return 'lost';
  return 'active';
}

/// CRM task → `todo | inprogress | blocked | done`.
/// The backend has no "blocked" type; a status the org *named* Blocked maps
/// there, and the `cancelled` type also lands on `blocked` (closest visual:
/// red, not progressing) since the UI has no cancelled bucket.
String crmTaskStatusKey({String? name, String? type}) {
  final n = _norm(name);
  if (n.contains('block')) return 'blocked';
  if (n.contains('progress')) return 'inprogress';
  if (n.contains('done') || n.contains('complete')) return 'done';
  switch (_norm(type)) {
    case 'in_progress':
      return 'inprogress';
    case 'completed':
      return 'done';
    case 'cancelled':
      return 'blocked';
    default:
      return 'todo';
  }
}

/// Follow-up → `overdue | due | done`, derived from completion + due date.
String followupStatusKey({required bool isCompleted, DateTime? dueDate, DateTime? now}) {
  if (isCompleted) return 'done';
  if (dueDate == null) return 'due';
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
  return due.isBefore(today) ? 'overdue' : 'due';
}

/// Quote → `draft | sent | accepted | rejected | expired`.
/// A sent quote past its validity date renders as expired (effective status).
String quoteStatusKey({String? name, DateTime? validUntil, bool isConverted = false, DateTime? now}) {
  final n = _norm(name);
  String key;
  if (isConverted || n.contains('accept')) {
    key = 'accepted';
  } else if (n.contains('reject') || n.contains('decline')) {
    key = 'rejected';
  } else if (n.contains('expire')) {
    key = 'expired';
  } else if (n.contains('sent')) {
    key = 'sent';
  } else {
    key = 'draft';
  }
  if ((key == 'sent' || key == 'draft') && validUntil != null) {
    final ref = now ?? DateTime.now();
    if (validUntil.isBefore(DateTime(ref.year, ref.month, ref.day))) {
      key = 'expired';
    }
  }
  return key;
}

/// Payment record → `paid | due | overdue | scheduled`.
/// API statuses are `paid|pending|overdue|cancelled`; pending splits into
/// `due` (today/past window) vs `scheduled` (future) by due date. Cancelled
/// rows should be skipped by callers before mapping.
String paymentStatusKey({String? status, DateTime? dueDate, DateTime? now}) {
  switch (_norm(status)) {
    case 'paid':
      return 'paid';
    case 'overdue':
      return 'overdue';
  }
  if (dueDate != null) {
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    if (due.isBefore(today)) return 'overdue';
    if (due.isAfter(today)) return 'scheduled';
  }
  return 'due';
}

/// Invoice (quotation Payment) → `unpaid | partial | completed`.
String invoiceStatusKey({String? status, double amountPaid = 0}) {
  if (_norm(status) == 'completed') return 'completed';
  return amountPaid > 0 ? 'partial' : 'unpaid';
}

/// Project → `planning | active | onhold | completed | cancelled`.
String projectStatusKey({String? name, bool isClosed = false}) {
  final n = _norm(name);
  if (n.contains('plan')) return 'planning';
  if (n.contains('hold') || n.contains('pause')) return 'onhold';
  if (n.contains('cancel')) return 'cancelled';
  if (n.contains('complete') || n.contains('done')) return 'completed';
  if (n.contains('active') || n.contains('progress')) return 'active';
  return isClosed ? 'completed' : 'active';
}

/// PMO task → `open | working | review | completed | cancelled`.
String opsTaskStatusKey({String? name, bool isClosed = false, bool isCancelled = false}) {
  final n = _norm(name);
  if (n.contains('review')) return 'review';
  if (n.contains('working') || n.contains('progress')) return 'working';
  if (n.contains('cancel') || isCancelled) return 'cancelled';
  if (n.contains('complete') || n.contains('done')) return 'completed';
  if (isClosed) return 'completed';
  return 'open';
}

/// Helpdesk ticket → `new | open | pending | resolved | closed`.
String ticketStatusKey(String? name) {
  final n = _norm(name);
  if (n.contains('new')) return 'new';
  if (n.contains('pending') || n.contains('hold') || n.contains('wait')) {
    return 'pending';
  }
  if (n.contains('resolve')) return 'resolved';
  if (n.contains('close')) return 'closed';
  return 'open';
}

/// Priorities are capitalized display strings in the UI (`Urgent|High|Medium|Low`).
///
/// `critical` is the top level in the seeded org catalog and has no built-in
/// counterpart; it folds into `Urgent` rather than falling through to the
/// `Medium` default, which used to show the org's most severe tasks as ordinary
/// ones.
String priorityKey(String? value) {
  final n = _norm(value);
  if (n.startsWith('urg') || n.startsWith('crit')) return 'Urgent';
  if (n.startsWith('hi')) return 'High';
  if (n.startsWith('lo')) return 'Low';
  return 'Medium';
}
