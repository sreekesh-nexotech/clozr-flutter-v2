// Quote lifecycle rules for the detail screen — a port of the webapp's
// `quoteLifecycle.ts`, `acceptPlanSummary.ts`, `quoteLock.ts` and the
// detail screen's gating. Pure Dart over the raw quote record
// (`GET /quotations/quotations/{uuid}/`), so every rule is unit-tested.

import '../../../core/network/app_error.dart';
import 'quote_discount_approval_rules.dart' as approval;

// ── Small helpers ─────────────────────────────────────────────────────────

String _s(Object? v) {
  if (v == null) return '';
  final t = '$v'.trim();
  return t == 'null' ? '' : t;
}

int? _int(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse(_s(v));
}

final _ymd = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// `YYYY-MM-DD` of a local date.
String isoDayOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The local calendar day of an ISO date / timestamp ('' when unparseable).
String localDayOf(String iso) {
  final t = iso.trim();
  if (t.isEmpty) return '';
  if (_ymd.hasMatch(t)) return t;
  final d = DateTime.tryParse(t);
  return d == null ? '' : isoDayOf(d.toLocal());
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Webapp `fmtIsoDate` — `2026-10-10` / an ISO timestamp → `10-Oct-2026`;
/// '' when unparseable.
String fmtQuoteDate(String? iso) {
  final day = localDayOf(iso ?? '');
  if (day.isEmpty) return '';
  final d = DateTime.parse(day);
  return '${d.day.toString().padLeft(2, '0')}-${_months[d.month - 1]}-${d.year}';
}

/// Webapp `humanizeEnum`: `installment_even` → `Installment even`.
String humanizeEnum(String value) {
  final words = value.replaceAll(RegExp(r'[_\-\s]+'), ' ').trim().toLowerCase();
  return words.isEmpty ? '' : words[0].toUpperCase() + words.substring(1);
}

const _planTypeLabel = {
  'lumpsum': 'Lump sum',
  'subscription': 'Subscription',
  'installment_even': 'Instalments – even split',
  'installment_custom': 'Milestone-based',
};

/// Webapp `planTypeLabel`.
String planTypeLabel(String? value) {
  final k = _s(value);
  if (k.isEmpty) return '';
  return _planTypeLabel[k] ?? _planTypeLabel[k.toLowerCase()] ?? humanizeEnum(k);
}

/// Webapp `AMOUNTS_ARE_LABEL`.
String amountsAreLabel(String? value) {
  final k = _s(value).toUpperCase();
  if (k.isEmpty) return '';
  return switch (k) { 'EXCLUSIVE' => 'Tax exclusive', 'INCLUSIVE' => 'Tax inclusive', _ => humanizeEnum(k) };
}

// ── Statuses ──────────────────────────────────────────────────────────────

const quoteStatusTypes = ['DRAFT', 'SENT', 'ACCEPTED', 'REJECTED', 'EXPIRED', 'SUPERSEDED'];

/// One `/quotations/statuses/` row, with the meaning (`status_type`) the
/// lifecycle rules read. Inactive rows are kept (the picker hides them).
class QuoteStatusRow {
  const QuoteStatusRow({
    required this.id,
    required this.name,
    this.color,
    this.isConverted = false,
    this.isDefault = false,
    this.isActive = true,
    this.statusType,
  });

  final String id;
  final String name;

  /// `#RRGGBB` as sent.
  final String? color;
  final bool isConverted;
  final bool isDefault;
  final bool isActive;
  final String? statusType;

  static String? _type(Object? v) {
    final t = _s(v).toUpperCase();
    return quoteStatusTypes.contains(t) ? t : null;
  }

  static QuoteStatusRow? fromJson(Map<String, dynamic> r) {
    final id = _s(r['quotation_status_id']);
    final name = _s(r['name']);
    if (id.isEmpty || name.isEmpty) return null;
    return QuoteStatusRow(
      id: id,
      name: name,
      color: _s(r['color']).isEmpty ? null : _s(r['color']),
      isConverted: r['is_converted'] == true,
      isDefault: r['is_default'] == true,
      isActive: r['is_active'] != false,
      statusType: _type(r['status_type']),
    );
  }
}

/// The status rows of a `/quotations/statuses/` body (paged or a bare list).
List<QuoteStatusRow> quoteStatusRows(Object? body) {
  final list = body is Map ? body['results'] : body;
  if (list is! List) return const [];
  return [
    for (final r in list)
      if (r is Map) QuoteStatusRow.fromJson(Map<String, dynamic>.from(r)),
  ].whereType<QuoteStatusRow>().toList();
}

const _legacyNameToType = {
  'draft': 'DRAFT',
  'sent': 'SENT',
  'accepted': 'ACCEPTED',
  'approved': 'ACCEPTED',
  'won': 'ACCEPTED',
  'rejected': 'REJECTED',
  'declined': 'REJECTED',
  'lost': 'REJECTED',
  'expired': 'EXPIRED',
  'superseded': 'SUPERSEDED',
};

/// True when no status carries a type — a backend predating status semantics.
bool isLegacyStatusList(List<QuoteStatusRow> statuses) =>
    statuses.isNotEmpty && statuses.every((s) => s.statusType == null);

/// What a status means; the label stands in only on a [legacy] list.
String? resolveStatusType(QuoteStatusRow? status, bool legacy) {
  if (status == null) return null;
  if (status.statusType != null) return status.statusType;
  if (status.isConverted) return 'ACCEPTED';
  if (legacy) return _legacyNameToType[status.name.trim().toLowerCase()];
  return null;
}

/// The status an action moves a quote into: the default of that type, else
/// the first active one; Accepted prefers the `is_converted` row.
QuoteStatusRow? findStatusOfType(List<QuoteStatusRow> statuses, String type) {
  final legacy = isLegacyStatusList(statuses);
  final matching = [
    for (final s in statuses)
      if (s.isActive && resolveStatusType(s, legacy) == type) s,
  ];
  if (matching.isEmpty) return null;
  if (type == 'ACCEPTED') {
    return matching.where((s) => s.isConverted).firstOrNull ??
        matching.where((s) => s.isDefault).firstOrNull ??
        matching.first;
  }
  return matching.where((s) => s.isDefault).firstOrNull ?? matching.first;
}

/// Statuses a user may pick: Superseded, deactivated and (once sent) Draft
/// are hidden — unless current.
List<QuoteStatusRow> pickableStatuses(List<QuoteStatusRow> statuses, String currentId, {bool wasSent = false}) {
  final legacy = isLegacyStatusList(statuses);
  return [
    for (final s in statuses)
      if (s.id == currentId ||
          (s.isActive &&
              resolveStatusType(s, legacy) != 'SUPERSEDED' &&
              !(wasSent && resolveStatusType(s, legacy) == 'DRAFT')))
        s,
  ];
}

/// Moving into a Rejected-type status asks for a decline reason.
bool needsDeclineReason(String? target, String? current) => target == 'REJECTED' && current != 'REJECTED';

const kStatusNotConfigured = 'That status isn’t configured for this workspace.';

// ── The quote facts ───────────────────────────────────────────────────────

/// The server's `acceptance_block` (the 409 a move into Accepted would answer).
class AcceptanceBlock {
  const AcceptanceBlock({
    required this.code,
    required this.message,
    this.next = '',
    this.acceptedQuotationId = '',
    this.acceptedQuotationNumber = '',
    this.acceptedOnMax = '',
    this.acceptedOnMin = '',
  });

  final String code;
  final String message;
  final String next;
  final String acceptedQuotationId;
  final String acceptedQuotationNumber;
  final String acceptedOnMax;
  final String acceptedOnMin;

  static AcceptanceBlock? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final cause = raw['cause'] is Map ? raw['cause'] as Map : const {};
    return AcceptanceBlock(
      code: _s(raw['code']),
      message: _s(raw['detail']),
      next: _s(raw['next']),
      acceptedQuotationId: _s(cause['accepted_quotation_id']),
      acceptedQuotationNumber: _s(cause['accepted_quotation_number']),
      acceptedOnMax: _s(cause['accepted_on_max']),
      acceptedOnMin: _s(cause['accepted_on_min']),
    );
  }
}

/// The quote record facts the rules read.
class QuoteFacts {
  const QuoteFacts({
    this.id = '',
    this.number = '',
    this.title = '',
    this.statusId = '',
    this.statusName = '',
    this.statusType,
    this.isConverted = false,
    this.isLocked = false,
    this.sentAt = '',
    this.validUntil = '',
    this.dueDate = '',
    this.paymentPlanId = '',
    this.approvalStatus = 'NOT_REQUIRED',
    this.acceptanceBlock,
    this.lineCount,
    this.revisionNo = 0,
    this.revisionOf = '',
    this.paymentType = '',
    this.numInstallments,
    this.billingPeriodDays,
    this.grandTotal,
  });

  final String id;
  final String number;
  final String title;
  final String statusId;
  final String statusName;
  final String? statusType;
  final bool isConverted;
  final bool isLocked;
  final String sentAt;
  final String validUntil;
  final String dueDate;
  final String paymentPlanId;
  final String approvalStatus;
  final AcceptanceBlock? acceptanceBlock;

  /// Null when unknown (the org's layout hides the lines).
  final int? lineCount;
  final int revisionNo;
  final String revisionOf;
  final String paymentType;
  final int? numInstallments;
  final int? billingPeriodDays;

  /// `grand_total` (2-dp string incl. GST); null on an older backend.
  final String? grandTotal;

  /// Number, else title, else "this quote" — the dialogs' label.
  String get label => number.isNotEmpty ? number : (title.isNotEmpty ? title : 'this quote');

  /// Facts from a raw record. [statuses] resolves a status the record sends
  /// without a type (an older backend).
  factory QuoteFacts.fromRow(Map<String, dynamic> row, {List<QuoteStatusRow> statuses = const []}) {
    final status = row['status'];
    final statusMap = status is Map ? status : const {};
    final statusId = _s(statusMap['quotation_status_id']).isNotEmpty
        ? _s(statusMap['quotation_status_id'])
        : (status is String ? status : _s(row['status_id']));
    var type = QuoteStatusRow._type(statusMap['status_type']);
    final converted = statusMap['is_converted'] == true;
    if (type == null) {
      final match = statuses.where((s) => s.id == statusId).firstOrNull;
      type = resolveStatusType(match, isLegacyStatusList(statuses));
    }
    if (type == null && converted) type = 'ACCEPTED';
    final lines = row['line_items'] ?? row['items'];
    final plans = row['payment_plan_ids'];
    return QuoteFacts(
      id: _s(row['quotation_id']),
      number: _s(row['quotation_number']),
      title: _s(row['quotation_title']),
      statusId: statusId,
      statusName: _s(statusMap['name']),
      statusType: type,
      isConverted: converted,
      isLocked: row['is_locked'] == true,
      sentAt: _s(row['sent_at']),
      validUntil: _s(row['valid_until']),
      dueDate: _s(row['due_date']),
      paymentPlanId: _s(row['payment_plan_id']).isNotEmpty
          ? _s(row['payment_plan_id'])
          : (plans is List && plans.isNotEmpty ? _s(plans.first) : ''),
      approvalStatus: approval.quoteApprovalStatus(row),
      acceptanceBlock: AcceptanceBlock.fromJson(row['acceptance_block']),
      lineCount: lines is List ? lines.length : null,
      revisionNo: _int(row['revision_no']) ?? 0,
      revisionOf: _s(row['revision_of']),
      paymentType: _s(row['payment_type']),
      numInstallments: _int(row['num_installments']),
      billingPeriodDays: _int(row['billing_period_days']),
      grandTotal: _s(row['grand_total']).isEmpty ? null : _s(row['grand_total']),
    );
  }
}

/// What the detail screen offers for a quote (webapp `QuoteLifecycleActions`).
class QuoteLifecycleActions {
  const QuoteLifecycleActions({
    required this.isSuperseded,
    required this.isAccepted,
    required this.isExpired,
    required this.canMarkSent,
    required this.sendBlocked,
    required this.sendBlockedReason,
    required this.canAccept,
    required this.acceptBlockedReason,
    required this.canReject,
    required this.canRevise,
    required this.canRenew,
    required this.wasSent,
  });

  final bool isSuperseded;
  final bool isAccepted;
  final bool isExpired;

  /// "Mark as sent" is offered (a draft / untyped status).
  final bool canMarkSent;

  /// …but greyed, with [sendBlockedReason].
  final bool sendBlocked;
  final String sendBlockedReason;

  /// Accept is offered…
  final bool canAccept;

  /// …and greyed when this is not '' (the reason).
  final String acceptBlockedReason;
  bool get acceptBlocked => acceptBlockedReason.isNotEmpty;

  final bool canReject;
  final bool canRevise;
  final bool canRenew;

  /// Sent at some point: Draft is no longer offered by the status picker.
  final bool wasSent;

  /// Superseded revisions are read-only (no write of any kind).
  bool get isReadOnly => isSuperseded;
}

const kSendNeedsLine = 'Add a line item before sending this quote.';
const kSendNeedsValidity = 'Set a “Valid until” date before sending this quote.';
const kSendValidityPassed = 'This quote’s validity date has passed — set a new “Valid until” date before sending it.';
const kAcceptNotSent = 'Mark the quote as sent before accepting it.';
const kAcceptExpired = 'This quote has expired — renew it to accept the current prices.';

/// R4 — only a back-dated acceptance (≤ `valid_until`) can get it accepted.
bool canBackdateAcceptance(AcceptanceBlock? block) =>
    block != null && block.code == 'QUOTE_EXPIRED' && block.acceptedOnMax.isNotEmpty;

/// The webapp's `quoteLifecycleActions`, plus the discount-approval copy for
/// the send block (pending / rejected approval).
QuoteLifecycleActions quoteLifecycleActions(QuoteFacts q, {DateTime? today, Map<String, dynamic>? row}) {
  final now = today ?? DateTime.now();
  final type = q.statusType;
  final isSuperseded = type == 'SUPERSEDED';
  final isAccepted = type == 'ACCEPTED' || q.isConverted;
  final isOpen = type == null || type == 'DRAFT' || type == 'SENT';
  final validDay = localDayOf(q.validUntil);
  final pastValidity = validDay.isNotEmpty && validDay.compareTo(isoDayOf(now)) < 0;
  final isExpired = !isAccepted && !isSuperseded && (type == 'EXPIRED' || (isOpen && pastValidity));
  final isDraftLike = (type == null || type == 'DRAFT') && !isAccepted;
  final wasSent = type == 'SENT' || type == 'REJECTED' || (q.isLocked && q.sentAt.isNotEmpty);
  final backdatable = canBackdateAcceptance(q.acceptanceBlock);
  final canAccept = (isOpen || (backdatable && type == 'EXPIRED')) && !isAccepted;
  final sent = type == 'SENT' || q.sentAt.isNotEmpty;
  var acceptReason = '';
  if (canAccept && !backdatable) {
    if (q.acceptanceBlock != null) {
      acceptReason = q.acceptanceBlock!.message.isEmpty ? 'This quote can’t be accepted right now.' : q.acceptanceBlock!.message;
    } else if (q.approvalStatus == 'PENDING' || q.approvalStatus == 'REJECTED') {
      acceptReason = approval.kAcceptNeedsApproval;
    } else if (!sent) {
      acceptReason = kAcceptNotSent;
    } else if (isExpired) {
      acceptReason = kAcceptExpired;
    }
  }
  var contentBlock = '';
  if (isDraftLike && q.sentAt.isEmpty) {
    if (q.lineCount == 0) {
      contentBlock = kSendNeedsLine;
    } else if (q.validUntil.isEmpty) {
      contentBlock = kSendNeedsValidity;
    } else if (pastValidity) {
      contentBlock = kSendValidityPassed;
    }
  }
  final approvalReason = switch (q.approvalStatus) {
    'PENDING' => approval.kMarkSentPendingApproval,
    'REJECTED' => approval.kMarkSentRejectedApproval,
    _ => '',
  };
  final sendReason = contentBlock.isNotEmpty ? contentBlock : approvalReason;
  return QuoteLifecycleActions(
    isSuperseded: isSuperseded,
    isAccepted: isAccepted,
    isExpired: isExpired,
    canMarkSent: isDraftLike,
    sendBlocked: sendReason.isNotEmpty,
    sendBlockedReason: sendReason,
    canAccept: canAccept,
    acceptBlockedReason: acceptReason,
    canReject: isOpen && !isAccepted,
    canRevise: wasSent && !isAccepted && !isSuperseded && !isExpired && q.paymentPlanId.isEmpty,
    canRenew: isExpired,
    wasSent: wasSent || q.sentAt.isNotEmpty || q.isConverted || type == 'ACCEPTED',
  );
}

// ── Delete ────────────────────────────────────────────────────────────────

const kDeleteBlocked = 'Accepted or paid quotes can’t be deleted — cancel or credit-note in accounting first';

/// Why Delete is greyed ('' when allowed): an accepted quote, or one with a
/// payment plan.
String deleteBlockedReason(QuoteFacts q) =>
    (q.isConverted || q.statusType == 'ACCEPTED' || q.paymentPlanId.isNotEmpty) ? kDeleteBlocked : '';

// ── Accept dialog ─────────────────────────────────────────────────────────

/// The "Accepted on" window (`YYYY-MM-DD`; [min] '' = no floor).
class AcceptDateWindow {
  const AcceptDateWindow({required this.min, required this.max, required this.initial, required this.backdatedOnly});
  final String min;
  final String max;
  final String initial;
  final bool backdatedOnly;
}

AcceptDateWindow acceptDateWindow(QuoteFacts q, {DateTime? today}) {
  final todayIso = isoDayOf(today ?? DateTime.now());
  final block = q.acceptanceBlock;
  if (canBackdateAcceptance(block)) {
    final max = block!.acceptedOnMax.compareTo(todayIso) < 0 ? block.acceptedOnMax : todayIso;
    return AcceptDateWindow(
        min: block.acceptedOnMin.isNotEmpty ? block.acceptedOnMin : localDayOf(q.sentAt), max: max, initial: max, backdatedOnly: true);
  }
  return AcceptDateWindow(min: localDayOf(q.sentAt), max: todayIso, initial: todayIso, backdatedOnly: false);
}

/// The hint under "Accepted on".
String acceptDateHint(AcceptDateWindow w) => w.backdatedOnly
    ? 'This quote was valid until ${w.max}. Enter the date the customer accepted — on or before that day.'
    : 'The day the customer accepted. Change it if you are recording an earlier acceptance.';

/// Why an "Accepted on" value is refused, or null.
String? validateAcceptedOn(String value, AcceptDateWindow w) {
  if (!_ymd.hasMatch(value)) return 'Pick the date the customer accepted.';
  if (value.compareTo(w.max) > 0) {
    return w.backdatedOnly
        ? 'The quote expired after ${w.max} — pick a date on or before it, or renew the quote.'
        : 'The acceptance date can’t be in the future.';
  }
  if (w.min.isNotEmpty && value.compareTo(w.min) < 0) {
    return 'The acceptance date can’t be before the quote was sent (${w.min}).';
  }
  return null;
}

/// The plan schedule chosen at acceptance (`schedule` in the PATCH body).
class AcceptSchedule {
  const AcceptSchedule({required this.numInstallments, required this.billingPeriodDays, required this.firstDueDate});
  final int numInstallments;
  final int billingPeriodDays;
  final String firstDueDate;

  Map<String, dynamic> toJson() =>
      {'num_installments': numInstallments, 'billing_period_days': billingPeriodDays, 'first_due_date': firstDueDate};
}

const kMaxInstalments = 60;
const kMaxPeriodDays = 366;
const _defaultPeriodDays = 30;
const kScheduleHelp = '1 instalment = lump sum. Until something is paid or invoiced the plan can still be re-split on its page.';

/// The first due date: the due date when on/after acceptance, else acceptance.
String planStartDate(String dueDate, String acceptedOn) {
  final due = localDayOf(dueDate);
  return due.isNotEmpty && due.compareTo(acceptedOn) >= 0 ? due : acceptedOn;
}

/// Whether the dialog offers the schedule (lump sum / even instalments).
bool scheduleEditable(String paymentType) => paymentType.isEmpty || paymentType == 'lumpsum' || paymentType == 'installment_even';

AcceptSchedule defaultSchedule(QuoteFacts q, String acceptedOn) {
  final even = q.paymentType == 'installment_even';
  return AcceptSchedule(
    numInstallments: even && (q.numInstallments ?? 0) > 0 ? q.numInstallments! : 1,
    billingPeriodDays: (q.billingPeriodDays ?? 0) > 0 ? q.billingPeriodDays! : _defaultPeriodDays,
    firstDueDate: planStartDate(q.dueDate, acceptedOn),
  );
}

int? _whole(String raw) => RegExp(r'^\d+$').hasMatch(raw.trim()) ? int.parse(raw.trim()) : null;

/// The schedule typed in the dialog ([firstDue] '' = the default start), or
/// an error. Returns `(schedule, error)`.
(AcceptSchedule?, String?) resolveSchedule(
    {required String count, required String periodDays, required String firstDue, required QuoteFacts quote, required String acceptedOn}) {
  final n = _whole(count);
  if (n == null || n < 1 || n > kMaxInstalments) return (null, 'Choose between 1 and $kMaxInstalments instalments.');
  final fallback = defaultSchedule(quote, acceptedOn);
  var period = fallback.billingPeriodDays;
  if (n > 1) {
    final p = _whole(periodDays);
    if (p == null || p < 1 || p > kMaxPeriodDays) return (null, 'The interval must be between 1 and $kMaxPeriodDays days.');
    period = p;
  }
  final first = firstDue.isNotEmpty ? firstDue : fallback.firstDueDate;
  if (!_ymd.hasMatch(first)) return (null, 'Pick the first due date.');
  if (first.compareTo(acceptedOn) < 0) {
    final shown = fmtQuoteDate(acceptedOn);
    return (null, 'The first instalment can’t be due before the acceptance date (${shown.isEmpty ? acceptedOn : shown}).');
  }
  return (AcceptSchedule(numInstallments: n, billingPeriodDays: period, firstDueDate: first), null);
}

/// True when the chosen schedule differs from the default (then it is sent).
bool scheduleChanged(AcceptSchedule chosen, QuoteFacts q, String acceptedOn) {
  final base = defaultSchedule(q, acceptedOn);
  if (chosen.numInstallments != base.numInstallments || chosen.firstDueDate != base.firstDueDate) return true;
  return chosen.numInstallments > 1 && chosen.billingPeriodDays != base.billingPeriodDays;
}

String _every(int p) => 'every $p day${p == 1 ? '' : 's'}';

/// "Lump sum, due 10-Oct-2026" / "3 instalments from 10-Oct-2026, every 30 days".
String scheduleSummary(AcceptSchedule s) {
  final start = fmtQuoteDate(s.firstDueDate).isEmpty ? s.firstDueDate : fmtQuoteDate(s.firstDueDate);
  if (s.numInstallments <= 1) return 'Lump sum, due $start';
  return '${s.numInstallments} instalments from $start, ${_every(s.billingPeriodDays)}';
}

/// The Accept dialog's plan box: type label, schedule line, amount
/// (already formatted by the caller from [QuoteFacts.grandTotal]).
({String typeLabel, String schedule}) acceptPlanSummary(QuoteFacts q, String acceptedOn) {
  final startIso = planStartDate(q.dueDate, acceptedOn);
  final start = fmtQuoteDate(startIso).isEmpty ? acceptedOn : fmtQuoteDate(startIso);
  final period = (q.billingPeriodDays ?? 0) > 0 ? q.billingPeriodDays! : _defaultPeriodDays;
  final type = q.paymentType.isEmpty ? 'lumpsum' : q.paymentType;
  final typeLabel = planTypeLabel(type);
  switch (type) {
    case 'lumpsum':
      return (typeLabel: typeLabel, schedule: 'Lump sum, due $start');
    case 'installment_even':
      final count = (q.numInstallments ?? 0) > 0 ? q.numInstallments! : 1;
      return (
        typeLabel: typeLabel,
        schedule: count == 1 ? '1 instalment, due $start' : '$count instalments from $start, ${_every(period)}'
      );
    case 'subscription':
      return (typeLabel: typeLabel, schedule: 'Subscription from $start, billed ${_every(period)}');
    case 'installment_custom':
      return (typeLabel: typeLabel, schedule: 'Milestone-based — add the milestones on the payment plan after accepting');
    default:
      return (typeLabel: typeLabel, schedule: '$typeLabel, from $start');
  }
}

// ── Decline / Renew ──────────────────────────────────────────────────────

const kDeclineNoteMax = 2000;
const kNoDeclineReasons =
    'No decline reasons are set up. An admin can add them under Settings › Quotes / Invoices › Decline reasons.';

/// `(reasonId, note)` to send, or the error. A reason is required and must
/// be one of [activeReasonIds]; the note is optional, trimmed and capped.
({String? error, String reasonId, String note}) validateDeclineDraft(String reasonId, String note, Iterable<String> activeReasonIds) {
  if (reasonId.isEmpty) return (error: 'Choose why the quote was declined.', reasonId: '', note: '');
  if (!activeReasonIds.contains(reasonId)) {
    return (error: 'That reason is no longer available — choose another.', reasonId: '', note: '');
  }
  final trimmed = note.trim();
  if (trimmed.length > kDeclineNoteMax) {
    return (error: 'Keep the note under $kDeclineNoteMax characters.', reasonId: '', note: '');
  }
  return (error: null, reasonId: reasonId, note: trimmed);
}

/// The renew dialog's date check: blank (server default) or after today.
String? validateRenewDate(String value, {DateTime? today}) {
  if (value.isEmpty) return null;
  final now = today ?? DateTime.now();
  final tomorrow = isoDayOf(DateTime(now.year, now.month, now.day + 1));
  return value.compareTo(tomorrow) < 0 ? 'Pick a date in the future, or leave it blank for the default validity.' : null;
}

// ── Conflicts / locks ────────────────────────────────────────────────────

const lifecycleConflictCodes = [
  'QUOTE_LOCKED',
  'QUOTE_NOT_REVISABLE',
  'QUOTE_NOT_EXPIRED',
  'APPROVAL_PENDING',
  'QUOTE_NOT_SENT',
  'QUOTE_EXPIRED',
  'ANOTHER_QUOTE_ACCEPTED',
  'QUOTE_HAS_PAYMENTS',
];
const _nextSteps = ['REVISE', 'RENEW', 'OPEN_LATEST_REVISION', 'WAIT_FOR_APPROVAL', 'MARK_SENT', 'OPEN_ACCEPTED_QUOTE'];

/// A 409 lifecycle refusal with the step the server suggests.
class LifecycleConflict {
  const LifecycleConflict({
    required this.code,
    required this.message,
    this.next,
    this.latestRevisionId = '',
    this.latestQuotationNumber = '',
    this.acceptedQuotationId = '',
    this.acceptedQuotationNumber = '',
  });

  final String code;
  final String message;
  final String? next;
  final String latestRevisionId;
  final String latestQuotationNumber;
  final String acceptedQuotationId;
  final String acceptedQuotationNumber;
}

/// Recognise a lifecycle 409 by its machine code; null for anything else.
LifecycleConflict? lifecycleConflict(Object? error) {
  if (error is! AppError || error.type != AppErrorType.conflict) return null;
  final code = error.code ?? '';
  if (!lifecycleConflictCodes.contains(code)) return null;
  final cause = error.causeMap;
  final next = error.nextAction;
  String str(String k) => cause[k] is String ? cause[k] as String : '';
  return LifecycleConflict(
    code: code,
    message: error.message,
    next: _nextSteps.contains(next) ? next : null,
    latestRevisionId: str('latest_revision_id'),
    latestQuotationNumber: str('latest_quotation_number'),
    acceptedQuotationId: str('accepted_quotation_id'),
    acceptedQuotationNumber: str('accepted_quotation_number'),
  );
}

enum QuoteLockKind { paid, revert }

const quoteLockCopy = {
  QuoteLockKind.paid: (
    title: 'This quote is locked.',
    body:
        'A payment has been recorded or a tax invoice is linked, so its amounts and tax details can no longer change. Create a new quote and cancel the existing invoice in Accounting instead.',
  ),
  QuoteLockKind.revert: (
    title: 'This quote can’t leave Accepted.',
    body: 'Its payment plan already has a tax invoice. Cancel the invoice, or raise a credit note, in Accounting first.',
  ),
};

/// Webapp `quoteLockKind`: a validation refusal while moving an accepted
/// quote off Accepted (or on `status_id`) is the revert block; any other
/// "…locked…" refusal is the paid lock.
QuoteLockKind? quoteLockKind(Object? error, {required bool wasStatusChange, required bool wasAccepted}) {
  if (error is! AppError || error.type != AppErrorType.validation) return null;
  if (wasStatusChange && (wasAccepted || (error.fieldErrors?.containsKey('status_id') ?? false))) return QuoteLockKind.revert;
  if (RegExp(r'\blocked\b', caseSensitive: false).hasMatch(error.bareMessage) ||
      RegExp(r'\blocked\b', caseSensitive: false).hasMatch(error.message)) {
    return QuoteLockKind.paid;
  }
  return null;
}

// ── Revisions ────────────────────────────────────────────────────────────

final _revisionSuffix = RegExp(r'-R(\d+)$');

/// `QTN-00012-R2` → `QTN-00012`.
String baseQuoteNumber(String number) => number.replaceAll(_revisionSuffix, '');

/// The newest revision in a chain from a search over the base number, or null.
Map<String, dynamic>? pickLatestRevision(List<Map<String, dynamic>> rows, QuoteFacts current) {
  final base = baseQuoteNumber(current.number);
  if (base.isEmpty) return null;
  Map<String, dynamic>? best;
  var bestNo = current.revisionNo;
  for (final r in rows) {
    final id = _s(r['quotation_id']);
    final number = _s(r['quotation_number']);
    if (id == current.id || baseQuoteNumber(number) != base) continue;
    final no = _int(r['revision_no']) ?? 0;
    if (no <= bestNo) continue;
    best = r;
    bestNo = no;
  }
  return best;
}

// ── Payment instructions ─────────────────────────────────────────────────

class QuoteBankAccount {
  const QuoteBankAccount({this.bankName = '', this.accountName = '', this.accountNumber = '', this.ifsc = '', this.branch = ''});
  final String bankName;
  final String accountName;
  final String accountNumber;
  final String ifsc;
  final String branch;
}

class QuotePaymentInstructions {
  const QuotePaymentInstructions({
    this.bankAccounts = const [],
    this.upiId = '',
    this.paymentLink = '',
    this.upiQrBase64 = '',
    this.amount = '0.00',
    this.note = '',
  });

  final List<QuoteBankAccount> bankAccounts;
  final String upiId;
  final String paymentLink;

  /// The base64 payload of a safe inline PNG / JPEG / WebP QR ('' otherwise).
  final String upiQrBase64;
  final String amount;
  final String note;

  /// `{payment_instructions: {...} | null}` → instructions, or null when none
  /// are set up.
  static QuotePaymentInstructions? fromResponse(Object? body) {
    final pi = body is Map ? body['payment_instructions'] : null;
    if (pi is! Map) return null;
    final qr = _s(pi['upi_qr_data_uri']);
    final m = RegExp(r'^data:image/(png|jpeg|webp);base64,([A-Za-z0-9+/=\s]+)$').firstMatch(qr);
    final link = _s(pi['payment_link']);
    return QuotePaymentInstructions(
      bankAccounts: [
        for (final b in (pi['bank_accounts'] is List ? pi['bank_accounts'] as List : const []))
          if (b is Map)
            QuoteBankAccount(
              bankName: _s(b['bank_name']),
              accountName: _s(b['account_name']),
              accountNumber: _s(b['account_number']),
              ifsc: _s(b['ifsc']),
              branch: _s(b['branch']),
            ),
      ],
      upiId: _s(pi['upi_id']),
      paymentLink: RegExp(r'^https?://', caseSensitive: false).hasMatch(link) ? link : '',
      upiQrBase64: m == null ? '' : m.group(2)!.replaceAll(RegExp(r'\s'), ''),
      amount: _s(pi['amount']).isEmpty ? '0.00' : _s(pi['amount']),
      note: _s(pi['note']),
    );
  }
}

const kNoPaymentInstructions = 'No payment instructions are set up for quotes.';

// ── Generate document ────────────────────────────────────────────────────

class DocTemplateField {
  const DocTemplateField({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.defaultValue = '',
    this.helpText = '',
    this.choices = const [],
  });
  final String key;
  final String label;
  final String type;
  final bool required;
  final String defaultValue;
  final String helpText;
  final List<String> choices;
}

class DocTemplate {
  const DocTemplate({required this.id, required this.name, this.description = '', this.fields = const []});
  final String id;
  final String name;
  final String description;
  final List<DocTemplateField> fields;

  static List<DocTemplate> listFrom(Object? body) {
    final list = body is Map ? body['results'] : body;
    if (list is! List) return const [];
    return [
      for (final r in list)
        if (r is Map && _s(r['template_id']).isNotEmpty)
          DocTemplate(
            id: _s(r['template_id']),
            name: _s(r['template_name']).isEmpty ? _s(r['name']) : _s(r['template_name']),
            description: _s(r['description']),
            fields: [
              for (final f in (r['field_definitions'] is List ? r['field_definitions'] as List : const []))
                if (f is Map && _s(f['field_key']).isNotEmpty)
                  DocTemplateField(
                    key: _s(f['field_key']),
                    label: _s(f['field_label']).isEmpty ? _s(f['field_key']) : _s(f['field_label']),
                    type: _s(f['field_type']).isEmpty ? 'text' : _s(f['field_type']),
                    required: f['is_required'] == true,
                    defaultValue: _s(f['default_value']),
                    helpText: _s(f['help_text']),
                    choices: [for (final c in (f['choices'] is List ? f['choices'] as List : const [])) _s(c)],
                  ),
            ],
          ),
    ];
  }
}

/// Webapp `documentFieldProblem` ('' = fine).
String documentFieldProblem(DocTemplateField f, String value) {
  final text = value.trim();
  if (text.isEmpty) return f.required && f.defaultValue.isEmpty ? '${f.label} is required.' : '';
  if ((f.type == 'number' || f.type == 'decimal') && double.tryParse(text.replaceAll(',', '')) == null) {
    return '${f.label} must be a number.';
  }
  if (f.type == 'date' && (!_ymd.hasMatch(text) || DateTime.tryParse(text) == null)) return '${f.label} must be a date.';
  return '';
}

/// The generate body: blank values are omitted so the server fills defaults.
Map<String, dynamic> generateDocumentBody(DocTemplate t, String quotationId, Map<String, String> values) => {
      'template_id': t.id,
      'quotation_id': quotationId,
      'field_values': {
        for (final f in t.fields)
          if ((values[f.key] ?? '').trim().isNotEmpty)
            f.key: f.type == 'number' || f.type == 'decimal'
                ? values[f.key]!.replaceAll(',', '').trim()
                : values[f.key]!.trim(),
      },
    };
