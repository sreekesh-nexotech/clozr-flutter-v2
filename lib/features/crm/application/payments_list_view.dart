import '../domain/entities/invoice.dart';
import '../domain/entities/payment.dart';
import 'customer_activity_view.dart' show activityMoney;

/// Pure presentation rules for CRM › Payments (both tabs), ported from the
/// webapp's `PaymentsListScreen` and `config/invoices.ts` so the mobile cards
/// show the same figures, labels and wording. No Flutter here — the cards map
/// [PayTone] to colours.

/// Webapp `money`: full Indian grouping, paise only when non-zero —
/// `₹12,34,567.50`, `₹100`, `-₹250`, `—` for null. Never abbreviated.
String payMoney(num? n) => activityMoney(n?.toDouble());

/// The colour family of a pill / date, as named by the webapp's meta.
enum PayTone { success, warning, danger, muted, info }

// ── Payment plans tab ──

/// "n/m settled" counts for one plan, from the payment records.
class PlanRecordCount {
  const PlanRecordCount(this.count, this.settled);
  final int count;
  final int settled;
}

/// Per-plan record counts keyed by the plan's uuid. As on web, every record
/// counts toward the total and "settled" means `settlement_state == paid`
/// (a record marked paid with GST still open is only partly paid).
Map<String, PlanRecordCount> planRecordCounts(Iterable<Payment> records) {
  final count = <String, int>{};
  final settled = <String, int>{};
  for (final r in records) {
    final key = r.planUuid;
    if (key == null || key.isEmpty) continue;
    count[key] = (count[key] ?? 0) + 1;
    if (r.settlementState == 'paid') settled[key] = (settled[key] ?? 0) + 1;
  }
  return {for (final e in count.entries) e.key: PlanRecordCount(e.value, settled[e.key] ?? 0)};
}

/// Webapp `settledLabel` — the PROGRESS cell: a recurring schedule counts
/// paid periods ("1 of 12 paid" / "3 paid · ongoing"); a whole-quote
/// subscription "{paid} of {scheduled} scheduled periods paid · ongoing";
/// otherwise "n/m settled" from the records, else "{pct}% settled".
String planProgressText(Invoice iv, {PlanRecordCount? counts}) {
  final rec = iv.recurring;
  if (rec != null) return rec.paidLabel;
  final sub = iv.subscription;
  if (sub != null) {
    return '${sub.periodsPaid} of ${sub.periodsScheduled} scheduled periods paid · ongoing';
  }
  if (iv.of > 0) return '${iv.settled}/${iv.of} settled';
  if (counts != null && counts.count > 0) return '${counts.settled}/${counts.count} settled';
  return '${iv.settledPct}% settled';
}

/// "2 periods open" / "1 period open".
String periodsText(int n, String what) => '$n period${n == 1 ? '' : 's'} $what';

/// "As quoted ₹X" when the incl.-GST figure differs from the quote-basis one.
String? asQuotedNote(double inclGst, double quoted) =>
    (inclGst - quoted).abs() >= 0.005 ? 'As quoted ${payMoney(quoted)}' : null;

/// The two money cells of a plan row (webapp `planListFigures`).
class PlanFigures {
  const PlanFigures({required this.total, required this.totalSub, required this.due, required this.dueSub});
  final double total;
  final String totalSub;
  final double due;
  final String dueSub;
}

/// TOTAL (INCL. GST) and AMOUNT DUE (INCL. GST), each with its sub-line: the
/// as-quoted figure when it differs, or — for a whole-quote subscription,
/// whose total is ONE period — "per <period>" and "N period(s) open".
PlanFigures planListFigures(Invoice iv) {
  final sub = iv.subscription;
  if (sub != null) {
    return PlanFigures(
      total: sub.amountPerPeriodInclGst,
      totalSub: 'per ${sub.periodLabel.isEmpty ? 'period' : sub.periodLabel}',
      due: iv.amountDueInclGstOrNet,
      dueSub: periodsText(sub.periodsOpen, 'open'),
    );
  }
  return PlanFigures(
    total: iv.totalInclGstOrNet,
    totalSub: asQuotedNote(iv.totalInclGstOrNet, iv.totalExact) ?? '',
    due: iv.amountDueInclGstOrNet,
    dueSub: asQuotedNote(iv.amountDueInclGstOrNet, iv.balanceExact) ?? '',
  );
}

/// Plan status pill tone: Unpaid grey, Partial amber, Completed green.
PayTone planStatusTone(String statusKey) => switch (statusKey) {
      'completed' => PayTone.success,
      'partial' => PayTone.warning,
      _ => PayTone.muted,
    };

/// The plan row's name: the customer, else the quote's lead (with a LEAD
/// badge — [isLead]), else an em dash. The plan list row carries no lead
/// name, so it comes from the plan's records ([leadName]).
({String name, bool isLead}) planWho(String? customer, String? leadName) {
  if (customer != null && customer.trim().isNotEmpty) return (name: customer, isLead: false);
  if (leadName != null && leadName.trim().isNotEmpty) return (name: leadName, isLead: true);
  return (name: '—', isLead: false);
}

/// The lead name of each plan, from its records (keyed by plan uuid).
Map<String, String> planLeadNames(Iterable<Payment> records) {
  final out = <String, String>{};
  for (final r in records) {
    final key = r.planUuid;
    final lead = r.leadName;
    if (key == null || lead == null || lead.isEmpty) continue;
    out.putIfAbsent(key, () => lead);
  }
  return out;
}

/// "6 payment plans" / "1 payment plan".
String planCountLabel(int n) => '$n payment plan${n == 1 ? '' : 's'}';

/// "19 payments" / "1 payment".
String paymentCountLabel(int n) => '$n payment${n == 1 ? '' : 's'}';

// ── Payments tab ──

/// Whether [p] belongs under a status chip. Mirrors what the webapp asks the
/// server for: Due **and** Scheduled both send `status=pending`, so both
/// list the pending records; Paid / Overdue pass through; All is everything.
bool paymentMatchesChip(Payment p, String chip) => switch (chip) {
      'all' => true,
      'due' || 'scheduled' => p.status == 'due',
      _ => p.status == chip,
    };

int paymentChipCount(Iterable<Payment> payments, String chip) =>
    payments.where((p) => paymentMatchesChip(p, chip)).length;

/// Webapp `settlementStateMeta`: Cancelled; an accounting adjustment (credit
/// note, refund, reversed receipt) wins over Paid; then Paid / Partly paid
/// from the server's settlement state; else Pending in the record-status
/// colour, so an overdue instalment stays red.
({String label, PayTone tone}) settlementPill(Payment p) {
  if (p.isCancelled) return (label: 'Cancelled', tone: PayTone.muted);
  switch (p.recordSummary?.adjustmentState) {
    case 'RECEIPT_REVERSED':
      return (label: 'Receipt reversed', tone: PayTone.danger);
    case 'REFUNDED':
      return (label: 'Refunded', tone: PayTone.muted);
    case 'PARTLY_REFUNDED':
      return (label: 'Partly refunded', tone: PayTone.warning);
    case 'CREDITED':
      return (label: 'Credited', tone: PayTone.muted);
    case 'PARTLY_CREDITED':
      return (label: 'Partly credited', tone: PayTone.warning);
  }
  switch (p.settlementState) {
    case 'paid':
      return (label: 'Paid', tone: PayTone.success);
    case 'partly_paid':
      return (label: 'Partly paid', tone: PayTone.warning);
  }
  final tone = switch (p.status) {
    'paid' => PayTone.success,
    'overdue' => PayTone.danger,
    'scheduled' => PayTone.info,
    _ => PayTone.warning,
  };
  return (label: 'Pending', tone: tone);
}

/// True when the incl.-GST figure differs from the stored (as-quoted) amount.
bool hasGstOnTop(Payment p) => (p.amountDueInclGst - p.amountExpected).abs() >= 0.005;

/// The small hint beside a record's main figure: where it comes from.
String amountDueHint(Payment p) => switch (p.amountDueBasis) {
      'INVOICE' => 'incl. GST · invoice',
      'ESTIMATE' => 'incl. GST · estimate',
      'AS_QUOTED' => 'as quoted',
      _ => hasGstOnTop(p) ? 'incl. GST' : '',
    };

/// "As quoted ₹X" under the figure, only when it differs.
String quotedAmountNote(Payment p) =>
    hasGstOnTop(p) ? 'As quoted ${payMoney(p.amountExpected)}' : '';

/// The PAYMENT cell's name: customer, else lead (+ LEAD badge), else the
/// quote number, else an em dash.
({String name, bool isLead}) paymentWho(Payment p, {String? resolvedCustomer}) {
  final company = (resolvedCustomer ?? p.custName ?? '').trim();
  if (company.isNotEmpty) return (name: company, isLead: false);
  final lead = (p.leadName ?? '').trim();
  if (lead.isNotEmpty) return (name: lead, isLead: true);
  final quote = (p.invId ?? '').trim();
  return (name: quote.isEmpty ? '—' : quote, isLead: false);
}

/// "<quote> · <label or Installment N>" + " · Linked to tax invoice".
String paymentSubLine(Payment p) {
  final quote = p.invId ?? p.planUuid ?? '';
  final label = p.label.isNotEmpty ? p.label : 'Installment ${p.installmentNumber}';
  return '$quote · $label${p.isLinkedToDocument ? ' · Linked to tax invoice' : ''}';
}

/// Plan type that takes record deletes — milestone-based only.
const milestonePlanType = 'installment_custom';

/// Whether a record may be deleted: the user holds payment delete, the
/// record sits on a milestone-based plan ([planType]) and it is neither
/// paid (nothing received on it) nor linked to a tax document — the server's
/// own rule, so the action is only offered where it can succeed.
bool canDeletePaymentRecord(Payment p, {required String? planType, required bool hasDeletePermission}) {
  if (!hasDeletePermission) return false;
  if (planType != milestonePlanType) return false;
  if (p.isCancelled || p.isLinkedToDocument) return false;
  if (p.status == 'paid' || p.settlementState != 'pending') return false;
  return p.amountPaid <= 0;
}

/// The webapp's delete confirm and result copy.
const deleteRecordTitle = 'Delete this payment record?';
const deleteRecordBody =
    "Only records on milestone-type payment plans can be deleted, and never a paid or invoiced one. "
    "The plan's totals are recalculated afterwards. This cannot be undone.";
const deleteRecordToast = 'Payment record deleted';
