// Pure rules for the payment-plan and payment-record detail screens — the
// webapp's `config/invoices.ts`, `config/planSchedule.ts`,
// `config/milestoneForm.ts`, `config/recurring.ts` and the header logic of
// `InvoiceDetailScreen.tsx` / `PaymentDetailScreen.tsx`, ported so mobile
// reads the same and the rules can be unit-tested without a widget.

import 'package:intl/intl.dart';

import '../customer_detail_rules.dart' show webMoney;
import 'payment_plan_detail.dart';

/// Webapp `money()`: `₹12,34,567.50`, `₹100` (paise only when non-zero),
/// `-₹250`, `—` for null.
String planMoney(num? n) => webMoney(n);

/// `2026-11-04` → `4 Nov 2026`; '' when blank / unparseable.
String planDate(String? iso) {
  if (iso == null || iso.trim().isEmpty) return '';
  final d = DateTime.tryParse(iso.trim());
  return d == null ? '' : DateFormat('d MMM yyyy').format(d);
}

// ── Labels ──

const Map<String, String> _planTypeLabels = {
  'lumpsum': 'Lump sum',
  'subscription': 'Subscription',
  'installment_even': 'Instalments – even split',
  'installment_custom': 'Milestone-based',
};

const Map<String, String> _methodLabels = {
  'upi': 'UPI',
  'neft': 'NEFT',
  'imps': 'IMPS',
  'rtgs': 'RTGS',
  'cash': 'Cash',
  'cheque': 'Cheque',
  'card': 'Card',
  'bank_transfer': 'Bank transfer',
  'gateway': 'Payment gateway',
  'razorpay': 'Razorpay',
  'auto_debit': 'Auto-debit',
  'other': 'Other',
};

/// `UPPER_SNAKE` / `lower_snake` → "Upper snake".
String humanizeEnum(String value) {
  final words = value.replaceAll(RegExp(r'[_\-\s]+'), ' ').trim().toLowerCase();
  return words.isEmpty ? '' : '${words[0].toUpperCase()}${words.substring(1)}';
}

/// "Lump sum", "Milestone-based", … ('' when blank).
String planTypeLabel(String ptype) {
  final k = ptype.trim().toLowerCase();
  if (k.isEmpty) return '';
  return _planTypeLabels[k] ?? humanizeEnum(k);
}

/// "UPI", "Bank transfer", … ('' when blank). Already-human labels pass through.
String paymentMethodLabel(String method) {
  final k = method.trim();
  if (k.isEmpty || k == '—') return '';
  return _methodLabels[k.toLowerCase()] ?? (k.contains('_') || k == k.toUpperCase() ? humanizeEnum(k) : k);
}

/// The header's type label: "Recurring" / "One-time part" / the plan type.
String planHeaderType(PlanDetail p) {
  if (p.recurring != null) return 'Recurring';
  if (p.chargeScope == 'one_time') return 'One-time part';
  final t = planTypeLabel(p.ptype);
  return t.isEmpty ? '—' : t;
}

// ── Status ──

/// The FE plan status: `unpaid | partial | completed` — the server's own
/// status first, then the settled balance.
String planStatusKey(PlanDetail p) {
  if (p.status == 'completed' || (p.total > 0 && p.balance <= 0)) return 'completed';
  if (p.paid <= 0 && p.balance >= p.total) return 'unpaid';
  return 'partial';
}

/// Records fully settled (`settlement_state == paid`), not merely status=paid.
int settledCount(PlanDetail p) => p.records.where((r) => r.settlementState == 'paid').length;

/// Records on the plan, falling back to `num_installments`.
int recordCount(PlanDetail p) =>
    p.records.isNotEmpty ? p.records.length : (p.numInstallments ?? 0);

/// The progress text under the header: the recurring / subscription header
/// when the server sends one, else "1 of 3 settled".
String planProgressLabel(PlanDetail p) {
  final r = p.recurring;
  if (r != null) return r.header.isNotEmpty ? r.header : r.periodsPaidLabel;
  final s = p.subscription;
  if (s != null && s.header.isNotEmpty) return s.header;
  return '${settledCount(p)} of ${recordCount(p)} settled';
}

/// The pill key of a record, from the server's `settlement_state`:
/// `cancelled`, an accounting adjustment (`CREDITED`, …), `paid`,
/// `partly_paid`, else `pending`.
String recordPillKey(PlanRecord r) {
  if (r.status == 'cancelled') return 'cancelled';
  if (r.adjustmentState.isNotEmpty) return r.adjustmentState;
  return switch (r.settlementState) {
    'paid' => 'paid',
    'partly_paid' => 'partly_paid',
    _ => 'pending',
  };
}

const Map<String, String> _pillLabels = {
  'cancelled': 'Cancelled',
  'paid': 'Paid',
  'partly_paid': 'Partly paid',
  'pending': 'Pending',
  'RECEIPT_REVERSED': 'Receipt reversed',
  'REFUNDED': 'Refunded',
  'PARTLY_REFUNDED': 'Partly refunded',
  'CREDITED': 'Credited',
  'PARTLY_CREDITED': 'Partly credited',
};

String recordPillLabel(PlanRecord r) {
  final k = recordPillKey(r);
  return _pillLabels[k] ?? humanizeEnum(k);
}

/// The date a row shows: paid date once paid, else "Overdue …" / "Due …".
String recordRowDate(PlanRecord r) {
  if (r.status == 'paid') {
    final d = planDate(r.paidDate);
    return d.isEmpty ? '—' : d;
  }
  final d = planDate(r.dueDate);
  if (d.isEmpty) return '—';
  if (r.status == 'overdue') return 'Overdue $d';
  if (r.status == 'due') return 'Due $d';
  return d;
}

/// Whether the incl.-GST figure differs from the stored (as-quoted) amount.
bool hasGstOnTop(PlanRecord r) => (r.amountDueInclGst - r.amountExpected).abs() >= 0.005;

/// Where a row's figure comes from.
String amountDueHint(PlanRecord r) => switch (r.amountDueBasis) {
      'INVOICE' => 'incl. GST · invoice',
      'ESTIMATE' => 'incl. GST · estimate',
      'AS_QUOTED' => 'as quoted',
      _ => hasGstOnTop(r) ? 'incl. GST' : '',
    };

/// "As quoted ₹20,999.67" when it differs from the main figure, else ''.
String quotedAmountNote(PlanRecord r) => hasGstOnTop(r) ? 'As quoted ${planMoney(r.amountExpected)}' : '';

/// Credit-note / refund lines on a plan or record ('' list when none).
List<String> adjustmentLines({required double credited, required double refunded, double refundNotDue = 0}) => [
      if (credited >= 0.005) 'Credited ${planMoney(credited)}',
      if (refunded >= 0.005) 'Refunded ${planMoney(refunded)}${refundNotDue >= 0.005 ? ' · deal closed, not due again' : ''}',
    ];

// ── KPIs ──

/// One header KPI. [tone] is `default | success | navy | muted`.
class PlanKpi {
  const PlanKpi(this.label, this.value, this.tone, [this.sub]);
  final String label;
  final double value;
  final String tone;
  final String? sub;
}

String? _asQuoted(double inclGst, double quoted) =>
    (inclGst - quoted).abs() >= 0.005 ? 'As quoted ${planMoney(quoted)}' : null;

String _periods(int n, String what) => '$n period${n == 1 ? '' : 's'} $what';

/// Header KPIs: "Total (incl. GST)" | "Paid" | "Amount due (incl. GST)"; with
/// accounting active, "Advance received" and "Invoiced" in place of "Paid". A
/// whole-quote subscription shows its per-period charge.
List<PlanKpi> planKpis(PlanDetail p, {required bool accountingActive}) {
  final sub = p.subscription;
  final total = sub != null
      ? PlanKpi(
          'Per period (incl. GST)',
          sub.amountPerPeriodInclGst,
          'default',
          '${sub.periodLabel.isNotEmpty ? 'Every ${sub.periodLabel}' : 'Every period'}'
              '${(sub.amountPerPeriodInclGst - sub.amountPerPeriod).abs() >= 0.005 ? ' · as quoted ${planMoney(sub.amountPerPeriod)}' : ''}')
      : PlanKpi('Total (incl. GST)', p.totalInclGst, 'default', _asQuoted(p.totalInclGst, p.total));
  final due = PlanKpi('Amount due (incl. GST)', p.amountDueInclGst, 'navy',
      sub != null ? _periods(sub.periodsOpen, 'open') : _asQuoted(p.amountDueInclGst, p.balance));
  if (!accountingActive) return [total, PlanKpi('Paid', p.paid, 'success'), due];
  return [
    total,
    PlanKpi('Advance received', p.advanceReceived, 'success'),
    PlanKpi('Invoiced', p.invoicedTotal, 'muted'),
    due,
  ];
}

// ── Actions ──

/// "Record payment" — a completed plan takes no more payments, and the user
/// must hold payment create.
bool canRecordPayment(PlanDetail p, {required bool canCreate}) =>
    planStatusKey(p) != 'completed' && !p.isCancelled && canCreate;

/// "Settle" on one row: not paid, not cancelled, and recording is allowed.
bool canSettleRecord(PlanRecord r, {required bool canRecord}) =>
    canRecord && r.status != 'paid' && r.status != 'cancelled';

/// Delete a record (PY-011): only on a milestone-type plan, never a paid or
/// invoiced (document-linked) record, and only with payment delete.
bool canDeleteRecord({required String planType, required PlanRecord record, required bool canDelete}) =>
    canDelete &&
    planType == 'installment_custom' &&
    record.status != 'paid' &&
    !record.isLinkedToDocument;

// ── Instalments re-split (PY-027) ──

const int maxInstalments = 60;
const int maxPeriodDays = 366;
const int defaultPeriodDays = 30;

/// The "Instalments" card shows only while the server says the schedule can
/// still change (nothing paid or invoiced), and never on a subscription.
bool canChooseInstalments(PlanDetail p) => p.scheduleEditable && p.ptype != 'subscription';

class ScheduleDraft {
  const ScheduleDraft({required this.count, required this.periodDays, required this.firstDueDate});
  final String count;
  final String periodDays;

  /// `YYYY-MM-DD` or ''.
  final String firstDueDate;
}

/// The plan's current split, else 3 instalments, 30 days apart.
ScheduleDraft initialScheduleDraft(PlanDetail p) {
  final dues = p.records.where((r) => r.status != 'cancelled' && r.dueDate.isNotEmpty).map((r) => r.dueDate).toList()
    ..sort();
  final n = p.numInstallments;
  final d = p.billingPeriodDays;
  return ScheduleDraft(
    count: '${n != null && n > 1 ? n : 3}',
    periodDays: '${d != null && d > 0 ? d : defaultPeriodDays}',
    firstDueDate: dues.isEmpty ? '' : dues.first,
  );
}

int? _whole(String raw) {
  final t = raw.trim();
  return RegExp(r'^\d+$').hasMatch(t) ? int.parse(t) : null;
}

/// Field errors: `count` / `periodDays`. Empty when the draft can be sent.
Map<String, String> validateScheduleDraft(ScheduleDraft d) {
  final out = <String, String>{};
  final c = _whole(d.count);
  if (c == null || c < 1 || c > maxInstalments) out['count'] = 'Enter 1 to $maxInstalments instalments.';
  final days = _whole(d.periodDays);
  if (days == null || days < 1 || days > maxPeriodDays) out['periodDays'] = 'Enter 1 to $maxPeriodDays days.';
  return out;
}

/// `POST payments/{id}/schedule/` body of a valid draft.
Map<String, dynamic> scheduleBody(ScheduleDraft d) => {
      'num_installments': int.parse(d.count.trim()),
      'billing_period_days': int.parse(d.periodDays.trim()),
      if (d.firstDueDate.isNotEmpty) 'first_due_date': d.firstDueDate,
    };

/// An approximate equal split: whole rupees, the last takes the remainder
/// (10,000 / 3 → 3,333 + 3,333 + 3,334).
List<double> previewSplit(double total, int count) {
  if (count < 1 || !total.isFinite || total <= 0) return const [];
  final each = (total / count).roundToDouble();
  return [
    for (var i = 0; i < count - 1; i++) each,
    ((total - each * (count - 1)) * 100).round() / 100,
  ];
}

/// "About 2 × ₹3,333 + ₹3,334 (incl. GST). …" — '' unless it is a real split.
String schedulePreviewText(double totalInclGst, ScheduleDraft d) {
  if (validateScheduleDraft(d).containsKey('count')) return '';
  final parts = previewSplit(totalInclGst, int.parse(d.count.trim()));
  if (parts.length < 2) return '';
  return 'About ${parts.length - 1} × ${planMoney(parts.first)} + ${planMoney(parts.last)} (incl. GST). '
      'The exact amounts add up to the plan total; the last instalment takes the remainder.';
}

/// The toast after a successful re-split, from the plan the server returned.
String scheduleSavedToast(PlanDetail saved) => saved.ptype == 'lumpsum'
    ? 'Plan set to a single payment'
    : 'Plan split into ${saved.records.where((r) => r.status != 'cancelled').length} instalments';

// ── Milestones (PY-028) ──

const int milestoneLabelMax = 120;

/// A milestone-based plan that is still open.
bool canAddMilestones(PlanDetail p) => p.ptype == 'installment_custom' && !p.isCancelled;

/// The total the "%" mode applies to: the quote's total incl. GST, else the plan's.
double milestoneBaseTotal(PlanDetail p) {
  final q = p.quotedTotalInclGst;
  return q != null && q > 0 ? q : p.totalInclGst;
}

double? _parseAmount(String raw) {
  final t = raw.replaceAll(RegExp(r'[₹,\s]'), '');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return null;
  return double.tryParse(t);
}

/// The amount incl. GST a draft stands for (a % → its share of [base], 2 dp);
/// null when not a positive number (or a % over 100).
double? milestoneAmount({required bool percent, required String amount, required double base}) {
  final n = _parseAmount(amount);
  if (n == null || n <= 0) return null;
  if (percent) {
    if (n > 100 || base <= 0) return null;
    return (base * n).round() / 100;
  }
  return (n * 100).round() / 100;
}

/// Field errors: `label` / `amount` / `dueDate`. Empty = valid.
Map<String, String> validateMilestone({
  required String label,
  required bool percent,
  required String amount,
  required String dueDate,
  required double base,
}) {
  final out = <String, String>{};
  final l = label.trim();
  if (l.isEmpty) {
    out['label'] = 'Name the milestone (e.g. Design sign-off).';
  } else if (l.length > milestoneLabelMax) {
    out['label'] = 'Keep it under $milestoneLabelMax characters.';
  }
  if (milestoneAmount(percent: percent, amount: amount, base: base) == null) {
    out['amount'] = percent ? 'Enter a percentage between 0 and 100.' : 'Enter an amount greater than 0.';
  }
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dueDate)) out['dueDate'] = 'Pick the date this milestone falls due.';
  return out;
}

/// The note under the amount: "₹40,000 incl. GST · ₹60,000 of the quote not
/// yet scheduled" ('' when nothing to say).
String milestoneAmountNote({
  required bool percent,
  required String amount,
  required double base,
  double? unscheduled,
}) {
  final a = milestoneAmount(percent: percent, amount: amount, base: base);
  final parts = <String>[];
  if (a != null && percent) parts.add('${planMoney(a)} incl. GST');
  if (unscheduled != null && unscheduled > 0.005) {
    if (a != null && a - unscheduled > 0.005) {
      parts.add('${planMoney(a - unscheduled)} more than the ${planMoney(unscheduled)} not yet scheduled');
    } else {
      parts.add('${planMoney(unscheduled)} of the quote not yet scheduled');
    }
  }
  return parts.join(' · ');
}

/// The intro line of the Add milestone sheet.
String milestoneIntro(String quoteNumber, double base) =>
    'A milestone is scheduled on ${quoteNumber.isEmpty ? 'this plan' : quoteNumber} with its own payment '
    'follow-up on its due date.${base > 0 ? ' Quote total ${planMoney(base)} incl. GST.' : ''}';

/// `POST /quotations/payment-records/` body of a milestone.
Map<String, dynamic> milestoneBody({
  required String planId,
  required String label,
  required double amountInclGst,
  required String dueDate,
}) {
  final l = label.trim();
  return {
    'payment': planId,
    'amount_incl_gst': ((amountInclGst * 100).round() / 100).toStringAsFixed(2),
    'amount_paid': '0',
    'status': 'pending',
    'due_date': dueDate,
    if (l.isNotEmpty) 'notes': l,
  };
}

String milestoneAddedToast(double amount) => 'Milestone added — ${planMoney(amount)} due, follow-up created';

const String noMilestonesText =
    'No milestones yet. Add each milestone with its amount and due date; it is then scheduled and followed up.';

// ── Recurring (PY-029) ──

/// The default "Stop recurring from": the next period not generated yet, else
/// the next one due, else the first.
String defaultStopFrom(PlanRecurring r) => r.nextPeriodStart.isNotEmpty
    ? r.nextPeriodStart
    : r.nextDueDate.isNotEmpty
        ? r.nextDueDate
        : r.firstPeriodStart;

String stopRecurringBody(String dateLabel) =>
    'No period starting on or after $dateLabel will be billed. Open periods from that date that are not invoiced '
    'are cancelled; invoiced or paid periods stay as they are (correct them in Accounts). This cannot be undone.';

/// The progress line under the recurring header.
String recurringProgressText(PlanRecurring r) {
  final base = '${r.periodsPaid} of ${r.periodsElapsed} period${r.periodsElapsed == 1 ? '' : 's'} '
      'due so far paid (${r.progressPct}%).';
  if (r.stopFrom.isNotEmpty) return '$base Recurring billing stops from ${planDate(r.stopFrom)}.';
  if (r.generationEnded) return '$base Every period of the term has been scheduled.';
  return base;
}

/// The other plan of a split quote, and the link's label — null when none.
(String planId, String label)? chargeSplitLink(PlanDetail p) {
  final s = p.chargeSplit;
  if (s == null) return null;
  final recurringSide = p.chargeScope == 'recurring';
  final other = recurringSide ? s.oneTimePlanId : s.recurringPlanId;
  if (other.isEmpty || other == p.id) return null;
  return (other, recurringSide ? 'Open the one-time plan' : 'Open the recurring schedule');
}

// ── Needs attention (PY-032) ──

const String customerRequired = 'CUSTOMER_REQUIRED';
const String milestonesRequired = 'MILESTONES_REQUIRED';
const String customerRequiredMessage = 'This quote has no customer yet. Convert the lead to a customer first.';

/// The items the banner shows: the server's `needs_attention`, as on web
/// (InvoiceDetailScreen reads `invoice.needsAttention` and derives nothing).
/// `CUSTOMER_REQUIRED` only appears once accounting skipped a due draft.
List<PlanAttention> effectiveNeedsAttention(PlanDetail p) => p.needsAttention;

/// The banner's line: the message (or a default), plus " · N instalment(s) blocked".
String attentionText(PlanAttention a) {
  final msg = a.message.isNotEmpty ? a.message : (a.code == customerRequired ? customerRequiredMessage : a.code);
  final n = a.recordIds.length;
  return n > 0 ? '$msg · $n instalment${n == 1 ? '' : 's'} blocked' : msg;
}

/// Whether a row carries the "Blocked: customer required" tag.
bool isBlockedForCustomer(PlanRecord r, List<PlanAttention> attention) =>
    r.invoiceBlockedReason == customerRequired ||
    attention.any((a) => a.code == customerRequired && a.recordIds.contains(r.id));

// ── Record detail (PY-035) ──

const Map<String, String> treatAsLabels = {'ADVANCE': 'Advance', 'CUSTOMER_CREDIT': 'Customer credit'};

/// The record detail's synthetic activity: (title, sub).
List<(String, String)> recordActivity(PlanRecord r) {
  final paid = r.status == 'paid';
  final plan = r.quoteNumber.isNotEmpty ? r.quoteNumber : r.planId;
  return [
    (paid ? 'Payment received' : 'Payment ${recordPillLabel(r).toLowerCase()}', recordRowDate(r)),
    ('Payment plan $plan created', 'System · On creation'),
  ];
}

const String deleteRecordTitle = 'Delete this payment record?';
const String deleteRecordBody =
    "Only records on milestone-type payment plans can be deleted, and never a paid or invoiced one. The plan's "
    'totals are recalculated afterwards. This cannot be undone.';
