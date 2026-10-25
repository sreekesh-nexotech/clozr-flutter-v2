import 'package:equatable/equatable.dart';

/// A CRM invoice. Fields mirror the prototype's `invoices` seed 1:1 so the mock
/// data source maps directly and the shape is API-ready.
class Invoice extends Equatable {
  /// The display id — the source quote's `quotation_number` when there is one,
  /// which is what the UI shows and what the route is keyed on.
  final String id;

  /// The record's `payment_id` UUID.
  ///
  /// Every per-record call addresses the invoice by this, never by [id]:
  /// `GET /quotations/payments/{payment_id}/` for the schema-driven detail
  /// panel and `.../summary/` for the totals. Empty for mock rows.
  final String uuid;

  final String? custId;

  /// The customer's display name, straight from the row.
  ///
  /// The list serializer sends `customer_name` and **no** `customer_id`, so
  /// resolving the party by id yielded null on every row and each card fell back
  /// to an em dash. Kept alongside [custId] rather than replacing it, so the id
  /// is still used when a payload does carry one.
  final String? custName;

  /// The source quote's `quotation_number` — a display id, used for the chip
  /// and to route to the quote detail.
  final String? quoteId;

  /// The source quote's `quotation` UUID.
  ///
  /// Needed because `payment` is **not** an accepted `related_to` model: the
  /// API's list is lead, deal, contact, customer, organization_contact,
  /// product, issue, task, project, project_task, quotation. So an invoice's
  /// notes hang off the quote it was raised from.
  final String? quoteUuid;
  /// The webapp plan-type label (`planTypeLabel(paymentType)`): Lump sum /
  /// Subscription / Instalments – even split / Milestone-based.
  final String type;
  final String total; // display, e.g. "₹18L"
  final int totalNum;
  final int settled;
  final int of;
  final String balance; // display, e.g. "₹0L"

  /// `amount_remaining` in whole rupees, or **null** when the row did not
  /// carry the field at all.
  ///
  /// This is the completion driver, and after the accounting change it is
  /// `total − settled`, where settled counts withheld tax as well as cash — so
  /// it is **not** `total − amount_paid` any more.
  ///
  /// Nullable on purpose: a missing field parses to 0, which is
  /// indistinguishable from "nothing left to pay". Treating those the same
  /// would make a row with no money information at all render as 100% settled.
  final int? remainingNum;

  /// `amount_paid` as the server reports it, in whole rupees.
  ///
  /// The header used to sum the paid rows of the installment schedule instead.
  /// That double-counted nothing but disagreed with the backend whenever a
  /// record was part-paid — the row carries `amount_paid` per record, while the
  /// schedule row only knows its full face value.
  final int paidNum;

  final String status; // key into StatusMeta$.invoice

  // ── Accounting (handover §9.2). All null when the org has no accounting. ──

  /// `INVOICE_ON_DUE | INVOICE_ON_COMPLETION | PERIODIC | MANUAL`.
  final String? billingMode;

  /// Issue due drafts automatically (INVOICE_ON_DUE / PERIODIC).
  final bool autoIssue;

  /// `EXCLUSIVE | INCLUSIVE`. Null on plans created before accounting — gate
  /// G9 wants it set, and it locks once a record is linked or receipted.
  final String? amountsAre;
  final String? projectId;
  final String? contractRef;

  const Invoice({
    required this.id,
    this.uuid = '',
    required this.custId,
    this.custName,
    required this.quoteId,
    this.quoteUuid,
    required this.type,
    required this.total,
    required this.totalNum,
    required this.settled,
    required this.of,
    required this.balance,
    this.remainingNum,
    this.paidNum = 0,
    required this.status,
    this.billingMode,
    this.autoIssue = false,
    this.amountsAre,
    this.projectId,
    this.contractRef,
    this.paymentType = '',
    this.backendStatus,
    this.totalExact = 0,
    this.paidExact = 0,
    this.balanceExact = 0,
    this.totalInclGst,
    this.amountDueInclGst,
    this.amountRemainingInclGst,
    this.quotedTotalInclGst,
    this.unscheduledInclGst,
    this.amountRefunded = 0,
    this.subscription,
    this.recurring,
    this.chargeScope,
    this.nextDue,
    this.numInstallments,
    this.billingPeriodDays,
    this.leadId,
  });

  // ── Webapp parity (payment-plan list, PY-002) — every figure is the server's ──

  /// `payment_type` as sent: `lumpsum | subscription | installment_even |
  /// installment_custom` ('' when absent). [type] is its display label.
  final String paymentType;

  /// The server's own `status`: `active | completed | cancelled`.
  final String? backendStatus;

  /// `total_amount`, `amount_paid` (cash), `amount_remaining` (total −
  /// settled) with paise — the plan's quote-basis (pre-GST) figures.
  final double totalExact;
  final double paidExact;
  final double balanceExact;

  /// `total_incl_gst` / `amount_due_incl_gst` / `amount_remaining_incl_gst`
  /// — the MAIN figures the webapp shows. Null on an older backend; use
  /// [totalInclGstOrNet] / [amountDueInclGstOrNet] to read them.
  final double? totalInclGst;
  final double? amountDueInclGst;
  final double? amountRemainingInclGst;

  /// `quoted_total_incl_gst` — the quote's grand total when the plan was
  /// created; `unscheduled_incl_gst` — on a milestone plan, the part no
  /// milestone covers yet. Null when absent.
  final double? quotedTotalInclGst;
  final double? unscheduledInclGst;

  /// `amount_refunded` (incl. GST); 0 when none.
  final double amountRefunded;

  /// `subscription` — a whole-quote subscription's per-period figures.
  final PlanSubscription? subscription;

  /// `recurring` — the header of a recurring schedule (a quote with recurring
  /// lines is split into a one-time plan and this one).
  final PlanRecurring? recurring;

  /// `charge_scope`: `one_time | recurring`; null for an ordinary plan.
  final String? chargeScope;

  /// `next_due_date`.
  final DateTime? nextDue;

  /// `num_installments`, `billing_period_days`; null when unset.
  final int? numInstallments;
  final int? billingPeriodDays;

  /// The quote's lead (`customer.lead_id`, detail payload only).
  final String? leadId;

  /// The plan was closed (a lost deal, a stopped schedule).
  bool get isCancelled => backendStatus == 'cancelled';

  /// Total incl. GST, falling back to the quote-basis total.
  double get totalInclGstOrNet => totalInclGst ?? totalExact;

  /// Amount due incl. GST, falling back to the quote-basis balance.
  double get amountDueInclGstOrNet => amountDueInclGst ?? balanceExact;

  /// Webapp `pct`: the settled share of `total_amount`, 0–100.
  int get settledPct => totalExact > 0
      ? (((totalExact - balanceExact) / totalExact) * 100).round().clamp(0, 100)
      : 0;

  /// What the plan has actually settled, in whole rupees.
  ///
  /// Derived from [remainingNum] rather than read from `amount_paid`, because
  /// those two stopped meaning the same thing: a record settled with tax
  /// withheld at source counts the TDS toward completion, so the **cash**
  /// figure (`amount_paid`) is smaller than the **settled** figure. Showing
  /// cash beside a balance computed from settled is what made the header read
  /// "TOTAL ₹1L · PAID ₹90K · BALANCE ₹0".
  int get settledNum {
    final r = remainingNum;
    if (r == null || totalNum <= 0) return 0;
    return (totalNum - r).clamp(0, totalNum);
  }

  /// The settled amount that did not arrive as cash — withheld tax, mostly.
  /// Zero on every plan until someone records a deduction.
  int get nonCashNum {
    final gap = settledNum - paidNum;
    return gap > 0 ? gap : 0;
  }

  /// Fraction of the plan settled (0..1).
  ///
  /// Prefers the record counts, but the **list** serializer carries no
  /// `records` array — only the detail does — so `of` was 0 on every list row
  /// and every card drew an empty bar labelled "0/0 settled". Falls back to the
  /// money, which the list row does carry.
  double get progress {
    if (of > 0) return settled / of;
    // Only when the row actually reported its outstanding balance.
    if (remainingNum == null || totalNum <= 0) return 0;
    return (settledNum / totalNum).clamp(0.0, 1.0);
  }

  /// Whether the "X/Y settled" caption has real counts behind it.
  bool get hasRecordCounts => of > 0;

  /// The same plan under another [id] — used to keep ids unique when two
  /// plans share a quote number. Every field must be listed here, or a new
  /// one silently resets on the renamed copy.
  Invoice withId(String newId) => Invoice(
        id: newId,
        uuid: uuid,
        custId: custId,
        custName: custName,
        quoteId: quoteId,
        quoteUuid: quoteUuid,
        type: type,
        total: total,
        totalNum: totalNum,
        settled: settled,
        of: of,
        balance: balance,
        remainingNum: remainingNum,
        paidNum: paidNum,
        status: status,
        billingMode: billingMode,
        autoIssue: autoIssue,
        amountsAre: amountsAre,
        projectId: projectId,
        contractRef: contractRef,
        paymentType: paymentType,
        backendStatus: backendStatus,
        totalExact: totalExact,
        paidExact: paidExact,
        balanceExact: balanceExact,
        totalInclGst: totalInclGst,
        amountDueInclGst: amountDueInclGst,
        amountRemainingInclGst: amountRemainingInclGst,
        quotedTotalInclGst: quotedTotalInclGst,
        unscheduledInclGst: unscheduledInclGst,
        amountRefunded: amountRefunded,
        subscription: subscription,
        recurring: recurring,
        chargeScope: chargeScope,
        nextDue: nextDue,
        numInstallments: numInstallments,
        billingPeriodDays: billingPeriodDays,
        leadId: leadId,
      );

  @override
  List<Object?> get props => [id];
}

/// `GET /quotations/payments/{payment_id}/summary/` — the server's own view of
/// an invoice's money and schedule (doc §2b).
///
/// Everything here is derivable client-side from the header row and its
/// records, and the app did derive it — but the server is the authority on
/// part-payments and on what counts as overdue, and it alone knows
/// `next_due_date`. Where the two disagree this wins.
class InvoiceSummary extends Equatable {
  const InvoiceSummary({
    this.totalNum = 0,
    this.paidNum = 0,
    this.remainingNum = 0,
    this.currency = 'INR',
    this.status = '',
    this.nextDue,
    this.totalRecords = 0,
    this.pendingRecords = 0,
    this.paidRecords = 0,
    this.overdueRecords = 0,
  });

  final int totalNum;
  final int paidNum;
  final int remainingNum;
  final String currency;

  /// The backend's raw status string (`partially_paid`, …), not a folded key.
  final String status;

  /// When the next unpaid record falls due. Null once everything is settled.
  final DateTime? nextDue;

  final int totalRecords;
  final int pendingRecords;
  final int paidRecords;

  /// Records past due and unpaid. The app has no way to compute this as the
  /// server does — it applies the org's own overdue rule.
  final int overdueRecords;

  /// See [Invoice.settledNum] — total minus what is still outstanding, which
  /// includes withheld tax as well as cash received.
  int get settledNum =>
      totalNum <= 0 ? 0 : (totalNum - remainingNum).clamp(0, totalNum);

  /// The settled amount that did not arrive as cash.
  int get nonCashNum {
    final gap = settledNum - paidNum;
    return gap > 0 ? gap : 0;
  }

  @override
  List<Object?> get props => [
        totalNum, paidNum, remainingNum, currency, status,
        nextDue, totalRecords, pendingRecords, paidRecords, overdueRecords,
      ];
}

/// `subscription` on a whole-quote subscription plan (UAT R2 QT-10): it bills
/// one period's charge every period until cancelled, so its `total_amount` is
/// ONE period. Every figure is the server's (incl. GST unless named).
class PlanSubscription extends Equatable {
  const PlanSubscription({
    this.periodLabel = '',
    this.amountPerPeriod = 0,
    this.amountPerPeriodInclGst = 0,
    this.periodsScheduled = 0,
    this.periodsPaid = 0,
    this.periodsOpen = 0,
    this.openEnded = true,
    this.amountScheduledInclGst = 0,
    this.amountDueNowInclGst = 0,
    this.nextDue,
    this.header = '',
  });

  /// "10 days", "month".
  final String periodLabel;
  final double amountPerPeriod;
  final double amountPerPeriodInclGst;
  final int periodsScheduled;
  final int periodsPaid;
  final int periodsOpen;
  final bool openEnded;
  final double amountScheduledInclGst;
  final double amountDueNowInclGst;
  final DateTime? nextDue;

  /// The server's one-line summary ("₹3,94,758 / 10 days (incl. GST) · …").
  final String header;

  @override
  List<Object?> get props => [
        periodLabel, amountPerPeriod, amountPerPeriodInclGst, periodsScheduled,
        periodsPaid, periodsOpen, openEnded, amountScheduledInclGst,
        amountDueNowInclGst, nextDue, header,
      ];
}

/// `recurring` on a recurring schedule (D-3(b)): the server generates its
/// periods on a rolling window. Progress is periods paid ÷ elapsed.
class PlanRecurring extends Equatable {
  const PlanRecurring({
    this.periodLabel = '',
    this.termPeriods,
    this.effectiveTermPeriods,
    this.ongoing = false,
    this.amountPerPeriod = 0,
    this.amountPerPeriodInclGst = 0,
    this.periodsGenerated = 0,
    this.periodsPaid = 0,
    this.periodsElapsed = 0,
    this.progressPct = 0,
    this.nextDue,
    this.firstPeriodStart,
    this.nextPeriodStart,
    this.generationEnded = false,
    this.stopFrom,
    this.canStop = false,
    this.header = '',
  });

  final String periodLabel;

  /// The term as sold; null = until cancelled.
  final int? termPeriods;

  /// The term after a stop ("N of M" uses this); null = ongoing.
  final int? effectiveTermPeriods;
  final bool ongoing;
  final double amountPerPeriod;
  final double amountPerPeriodInclGst;
  final int periodsGenerated;
  final int periodsPaid;
  final int periodsElapsed;

  /// 0–100.
  final int progressPct;
  final DateTime? nextDue;
  final DateTime? firstPeriodStart;
  final DateTime? nextPeriodStart;
  final bool generationEnded;
  final DateTime? stopFrom;
  final bool canStop;

  /// The server's one-line header ("₹2,360 / month · next due 24-Oct · 0 of 12 paid").
  final String header;

  /// Webapp `periodsPaidLabel`: "1 of 12 paid" / "3 paid · ongoing".
  String get paidLabel => effectiveTermPeriods != null
      ? '$periodsPaid of $effectiveTermPeriods paid'
      : '$periodsPaid paid · ongoing';

  @override
  List<Object?> get props => [
        periodLabel, termPeriods, effectiveTermPeriods, ongoing, amountPerPeriod,
        amountPerPeriodInclGst, periodsGenerated, periodsPaid, periodsElapsed,
        progressPct, nextDue, firstPeriodStart, nextPeriodStart,
        generationEnded, stopFrom, canStop, header,
      ];
}

/// Webapp `PLAN_TYPE_LABEL`.
const planTypeLabels = <String, String>{
  'lumpsum': 'Lump sum',
  'subscription': 'Subscription',
  'installment_even': 'Instalments – even split',
  'installment_custom': 'Milestone-based',
};

/// "Lump sum", "Milestone-based", … — case-insensitive; an unknown value is
/// humanised ("some_type" → "Some type"); '' → '—'.
String planTypeLabel(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return '—';
  final known = planTypeLabels[v.toLowerCase()];
  if (known != null) return known;
  final words = v.replaceAll(RegExp(r'[_\-\s]+'), ' ').trim().toLowerCase();
  return words[0].toUpperCase() + words.substring(1);
}

/// Webapp `deriveStatusKey`: the server's `completed` (or nothing left to
/// settle) is Completed; nothing paid and the full balance open is Unpaid;
/// anything else under `active` — any payment at all — is Partial. [balance]
/// is total − SETTLED (TDS included), so a TDS-settled plan completes.
String planStatusKey({
  required double paid,
  required double balance,
  required double total,
  String? backendStatus,
}) {
  if (backendStatus == 'completed' || (total > 0 && balance <= 0)) return 'completed';
  if (paid <= 0 && balance >= total) return 'unpaid';
  return 'partial';
}
