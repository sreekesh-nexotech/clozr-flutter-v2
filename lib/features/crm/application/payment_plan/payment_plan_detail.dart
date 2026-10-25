// The payment-plan detail and payment-record detail as the plan screens read
// them — parsed straight off `GET /quotations/payments/{payment_id}/` and
// `GET /quotations/payment-records/{record_id}/`.
//
// Kept separate from the list entities (`Invoice` / `Payment`) on purpose: the
// detail payload carries far more (incl.-GST figures, needs-attention items,
// recurring / subscription headers, per-record settlement state) and the list
// cards do not need any of it. Mirrors the webapp's `invoice.response.ts` /
// `paymentRecord.response.ts` mapping.

import 'dart:math' as math;

/// A number off the wire: JSON number or decimal string. 0 when absent.
double planNum(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : 0;
  if (v is String && v.trim().isNotEmpty) return double.tryParse(v.trim()) ?? 0;
  return 0;
}

/// Like [planNum], but null when the field is absent or blank.
double? planNumOrNull(Object? v) {
  if (v == null) return null;
  if (v is String && v.trim().isEmpty) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return double.tryParse(v.trim());
  return null;
}

String _str(Object? v) => v is String ? v : v == null ? '' : '$v';

Map<String, dynamic>? _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// `record_summary.document` — the tax invoice accounting issued (or drafted).
class PlanRecordDocument {
  const PlanRecordDocument({
    required this.id,
    this.number = '',
    this.status = '',
    this.paymentState = '',
    this.openBalance = '',
    this.grandTotal = '',
  });

  final String id;
  final String number;

  /// `DRAFT | ISSUED | CANCELLED | VOID_DRAFT`.
  final String status;

  /// `UNPAID | PARTIAL | PAID | NA`.
  final String paymentState;
  final String openBalance;
  final String grandTotal;
}

/// `record_summary.receipt` — the receipt the ledger posted.
class PlanRecordReceipt {
  const PlanRecordReceipt({
    required this.id,
    this.kind = '',
    this.status = '',
    this.amount = '',
    this.date = '',
  });

  final String id;
  final String kind;
  final String status;
  final String amount;
  final String date;
}

/// One payment record (an instalment / milestone / period) of a plan.
class PlanRecord {
  const PlanRecord({
    required this.id,
    this.installmentNumber = 0,
    this.planId = '',
    this.quoteNumber = '',
    this.customerName = '',
    this.leadName = '',
    this.productName = '',
    this.amountExpected = 0,
    this.amountPaid = 0,
    this.amountDueInclGst = 0,
    this.amountDueBasis = '',
    this.balanceDue = 0,
    this.settlementState = 'pending',
    this.status = 'due',
    this.dueDate = '',
    this.paidDate = '',
    this.label = '',
    this.method = '',
    this.tds = 0,
    this.bankCharge = 0,
    this.gstTds = 0,
    this.gstTcs = 0,
    this.gatewayRef = '',
    this.treatAs = '',
    this.servicePeriodStart = '',
    this.servicePeriodEnd = '',
    this.linkedDocumentId = '',
    this.postedReceiptId = '',
    this.invoiceBlockedReason = '',
    this.cancelReason = '',
    this.amountCredited = 0,
    this.amountRefunded = 0,
    this.amountRefundNotDue = 0,
    this.document,
    this.receipt,
    this.adjustmentState = '',
  });

  /// `record_id` — what every per-record call addresses.
  final String id;
  final int installmentNumber;

  /// The parent plan's `payment_id`.
  final String planId;
  final String quoteNumber;
  final String customerName;
  final String leadName;
  final String productName;

  /// The stored amount, on the quote's basis (pre-GST on an exclusive quote).
  final double amountExpected;
  final double amountPaid;

  /// The amount due **including GST** — the figure every row shows.
  final double amountDueInclGst;

  /// `INVOICE | ESTIMATE | AS_QUOTED`, or '' on an older backend.
  final String amountDueBasis;
  final double balanceDue;

  /// `pending | partly_paid | paid`.
  final String settlementState;

  /// FE vocab: `paid | overdue | cancelled | due` (backend `pending` → `due`).
  final String status;
  final String dueDate;
  final String paidDate;

  /// `notes` — the record's own label ("Installment 2 of 3", a milestone name).
  final String label;

  /// `payment_method` as sent (`bank_transfer`, `upi`, …); '' when not paid.
  final String method;
  final double tds;
  final double bankCharge;
  final double gstTds;
  final double gstTcs;
  final String gatewayRef;
  final String treatAs;
  final String servicePeriodStart;
  final String servicePeriodEnd;
  final String linkedDocumentId;
  final String postedReceiptId;
  final String invoiceBlockedReason;
  final String cancelReason;
  final double amountCredited;
  final double amountRefunded;
  final double amountRefundNotDue;
  final PlanRecordDocument? document;
  final PlanRecordReceipt? receipt;

  /// `record_summary.adjustments.state` (`CREDITED`, `REFUNDED`, …) or ''.
  final String adjustmentState;

  /// "Installment 2" when the record carries no label of its own.
  String get displayLabel => label.trim().isNotEmpty ? label.trim() : 'Installment $installmentNumber';

  /// Accounting has issued a document for it — delete / revert are blocked.
  bool get isLinkedToDocument => linkedDocumentId.isNotEmpty;

  static String _status(Object? be) => switch (_str(be)) {
        'paid' => 'paid',
        'overdue' => 'overdue',
        'cancelled' => 'cancelled',
        _ => 'due',
      };

  factory PlanRecord.fromJson(Map<String, dynamic> j) {
    final status = _status(j['status']);
    final rawSettlement = _str(j['settlement_state']);
    final settlement = const {'paid', 'partly_paid', 'pending'}.contains(rawSettlement)
        ? rawSettlement
        : (status == 'paid' ? 'paid' : 'pending');
    final expected = planNum(j['amount_expected']);
    final gross = planNumOrNull(j['amount_due_gross']) ?? expected;
    final dueIncl = planNumOrNull(j['amount_due_incl_gst']) ?? gross;
    final paid = planNum(j['amount_paid']);
    final tds = planNum(j['tds_deducted']);
    final bank = planNum(j['bank_charge']);
    final refunded = planNum(j['amount_refunded']);
    final refundNotDue = planNum(j['amount_refund_not_due']);
    final balance = planNumOrNull(j['balance_due']) ??
        (status == 'paid'
            ? math.max(0.0, ((gross - (paid + tds + bank - refunded + refundNotDue)) * 100).round() / 100)
            : gross);

    final summary = _map(j['record_summary']);
    final docMap = _map(summary?['document']);
    final recMap = _map(summary?['receipt']);
    final adjMap = _map(summary?['adjustments']);
    final product = j['product_name'];
    return PlanRecord(
      id: _str(j['record_id']).isNotEmpty ? _str(j['record_id']) : _str(j['id']),
      installmentNumber: (j['installment_number'] as num?)?.toInt() ?? 0,
      planId: _str(j['payment']).isNotEmpty ? _str(j['payment']) : _str(j['invoice_id']),
      quoteNumber: _str(j['quotation_number']),
      customerName: _str(j['customer_name']),
      leadName: _str(j['lead_name']),
      productName: product is List ? product.map(_str).where((s) => s.isNotEmpty).join(', ') : _str(product),
      amountExpected: expected,
      amountPaid: paid,
      amountDueInclGst: dueIncl,
      amountDueBasis: const {'INVOICE', 'ESTIMATE', 'AS_QUOTED'}.contains(_str(j['amount_due_basis']))
          ? _str(j['amount_due_basis'])
          : '',
      balanceDue: balance,
      settlementState: settlement,
      status: status,
      dueDate: _str(j['due_date']),
      paidDate: _str(j['paid_date']),
      label: _str(j['notes']),
      method: _str(j['payment_method']),
      tds: tds,
      bankCharge: bank,
      gstTds: planNum(j['gst_tds_deducted']),
      gstTcs: planNum(j['gst_tcs_deducted']),
      gatewayRef: _str(j['gateway_ref']),
      treatAs: _str(j['treat_as']),
      servicePeriodStart: _str(j['service_period_start']),
      servicePeriodEnd: _str(j['service_period_end']),
      linkedDocumentId: _str(j['linked_document_id']),
      postedReceiptId: _str(j['posted_receipt_id']),
      invoiceBlockedReason: _str(j['invoice_blocked_reason']),
      cancelReason: _str(j['cancel_reason']),
      amountCredited: planNum(j['amount_credited']),
      amountRefunded: refunded,
      amountRefundNotDue: refundNotDue,
      document: docMap == null || _str(docMap['document_id']).isEmpty
          ? null
          : PlanRecordDocument(
              id: _str(docMap['document_id']),
              number: _str(docMap['number']),
              status: _str(docMap['status']),
              paymentState: _str(docMap['payment_state']),
              openBalance: _str(docMap['open_balance']),
              grandTotal: _str(docMap['grand_total']),
            ),
      receipt: recMap == null || _str(recMap['receipt_id']).isEmpty
          ? null
          : PlanRecordReceipt(
              id: _str(recMap['receipt_id']),
              kind: _str(recMap['kind']),
              status: _str(recMap['status']),
              amount: _str(recMap['amount']),
              date: _str(recMap['receipt_date']),
            ),
      adjustmentState: _str(adjMap?['state']),
    );
  }
}

/// One `needs_attention` item: what accounting is waiting on a person for.
class PlanAttention {
  const PlanAttention({required this.code, this.message = '', this.recordIds = const []});

  /// `CUSTOMER_REQUIRED`, `MILESTONES_REQUIRED`, …
  final String code;
  final String message;
  final List<String> recordIds;
}

/// `recurring` — the recurring schedule header (null on every other plan).
class PlanRecurring {
  const PlanRecurring({
    this.periodLabel = '',
    this.effectiveTermPeriods,
    this.periodsPaid = 0,
    this.periodsElapsed = 0,
    this.progressPct = 0,
    this.nextDueDate = '',
    this.firstPeriodStart = '',
    this.nextPeriodStart = '',
    this.generationEnded = false,
    this.stopFrom = '',
    this.canStop = false,
    this.header = '',
  });

  final String periodLabel;
  final int? effectiveTermPeriods;
  final int periodsPaid;
  final int periodsElapsed;
  final int progressPct;
  final String nextDueDate;
  final String firstPeriodStart;
  final String nextPeriodStart;
  final bool generationEnded;
  final String stopFrom;
  final bool canStop;

  /// The server's one-liner: "₹2,360 / month · next due 24-Oct · 0 of 12 paid".
  final String header;

  /// "1 of 12 paid" / "3 paid · ongoing".
  String get periodsPaidLabel => effectiveTermPeriods != null
      ? '$periodsPaid of $effectiveTermPeriods paid'
      : '$periodsPaid paid · ongoing';

  static PlanRecurring? fromJson(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    return PlanRecurring(
      periodLabel: _str(j['period_label']),
      effectiveTermPeriods: (j['effective_term_periods'] as num?)?.toInt(),
      periodsPaid: (j['periods_paid'] as num?)?.toInt() ?? 0,
      periodsElapsed: (j['periods_elapsed'] as num?)?.toInt() ?? 0,
      progressPct: ((j['progress_pct'] as num?)?.toInt() ?? 0).clamp(0, 100),
      nextDueDate: _str(j['next_due_date']),
      firstPeriodStart: _str(j['first_period_start']),
      nextPeriodStart: _str(j['next_period_start']),
      generationEnded: j['generation_ended'] == true,
      stopFrom: _str(j['stop_from']),
      canStop: j['can_stop'] == true,
      header: _str(j['header']),
    );
  }
}

/// `subscription` — a whole-quote subscription's per-period figures.
class PlanSubscription {
  const PlanSubscription({
    this.periodLabel = '',
    this.amountPerPeriod = 0,
    this.amountPerPeriodInclGst = 0,
    this.periodsOpen = 0,
    this.header = '',
  });

  final String periodLabel;
  final double amountPerPeriod;
  final double amountPerPeriodInclGst;
  final int periodsOpen;
  final String header;

  static PlanSubscription? fromJson(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    return PlanSubscription(
      periodLabel: _str(j['period_label']),
      amountPerPeriod: planNum(j['amount_per_period']),
      amountPerPeriodInclGst: planNum(j['amount_per_period_incl_gst']),
      periodsOpen: (j['periods_open'] as num?)?.toInt() ?? 0,
      header: _str(j['header']),
    );
  }
}

/// `charge_split` — the quote's one-time plan and recurring schedule.
class PlanChargeSplit {
  const PlanChargeSplit({this.oneTimePlanId = '', this.recurringPlanId = '', this.label = ''});

  final String oneTimePlanId;
  final String recurringPlanId;

  /// "₹11,800 one-time + ₹2,360 / month".
  final String label;

  static PlanChargeSplit? fromJson(Object? raw) {
    final j = _map(raw);
    if (j == null || _map(j['recurring']) == null) return null;
    return PlanChargeSplit(
      oneTimePlanId: _str(_map(j['one_time'])?['payment_id']),
      recurringPlanId: _str(_map(j['recurring'])?['payment_id']),
      label: _str(j['label']),
    );
  }
}

/// A payment plan (backend `Payment`) with its records.
class PlanDetail {
  const PlanDetail({
    required this.id,
    this.quoteNumber = '',
    this.quotationUuid = '',
    this.customerId = '',
    this.customerName = '',
    this.leadId = '',
    this.ptype = '',
    this.status = '',
    this.total = 0,
    this.paid = 0,
    this.balance = 0,
    this.totalInclGst = 0,
    this.amountDueInclGst = 0,
    this.advanceReceived = 0,
    this.invoicedTotal = 0,
    this.quotedTotalInclGst,
    this.unscheduledInclGst,
    this.scheduleEditable = false,
    this.numInstallments,
    this.billingPeriodDays,
    this.nextDueDate = '',
    this.needsAttention = const [],
    this.chargeScope = '',
    this.recurring,
    this.subscription,
    this.chargeSplit,
    this.ownerName = '',
    this.ownerEmail = '',
    this.amountCredited = 0,
    this.amountRefunded = 0,
    this.records = const [],
  });

  /// `payment_id`.
  final String id;
  final String quoteNumber;
  final String quotationUuid;
  final String customerId;
  final String customerName;

  /// `customer.lead_id` when the server sends it; '' otherwise (resolved from
  /// the quote by the screen when needed).
  final String leadId;

  /// `lumpsum | installment_even | installment_custom | subscription`.
  final String ptype;

  /// The backend status (`active | completed | cancelled`).
  final String status;

  /// Stored (quote-basis) figures.
  final double total;
  final double paid;
  final double balance;

  /// Incl.-GST figures — the headline numbers.
  final double totalInclGst;
  final double amountDueInclGst;
  final double advanceReceived;
  final double invoicedTotal;
  final double? quotedTotalInclGst;
  final double? unscheduledInclGst;
  final bool scheduleEditable;
  final int? numInstallments;
  final int? billingPeriodDays;
  final String nextDueDate;
  final List<PlanAttention> needsAttention;

  /// `one_time | recurring` on a split quote, '' otherwise.
  final String chargeScope;
  final PlanRecurring? recurring;
  final PlanSubscription? subscription;
  final PlanChargeSplit? chargeSplit;
  final String ownerName;
  final String ownerEmail;
  final double amountCredited;
  final double amountRefunded;
  final List<PlanRecord> records;

  bool get isCancelled => status == 'cancelled';

  factory PlanDetail.fromJson(Map<String, dynamic> j) {
    final records = [
      for (final r in (j['records'] is List ? j['records'] as List : const []))
        if (r is Map) PlanRecord.fromJson(Map<String, dynamic>.from(r)),
    ];
    final total = planNum(j['total_amount']);
    final paid = planNum(j['amount_paid']);
    final balance = planNumOrNull(j['amount_remaining']) ?? (total - paid);
    final gross = planNumOrNull(j['gross_total']) ?? total;
    final grossDue = planNumOrNull(j['balance_due_gross']) ?? balance;
    final customer = _map(j['customer']);
    final ownerRaw = j['owner'];
    final owner = _map(ownerRaw);
    final ownerName = owner == null
        ? (ownerRaw is String && !_uuidLike.hasMatch(ownerRaw) ? ownerRaw : (ownerRaw is String ? 'Unknown user' : ''))
        : (_str(owner['name']).isNotEmpty
            ? _str(owner['name'])
            : _str(owner['full_name']).isNotEmpty
                ? _str(owner['full_name'])
                : (_str(owner['user_id']).isNotEmpty ? 'Unknown user' : ''));
    final attention = <PlanAttention>[
      for (final a in (j['needs_attention'] is List ? j['needs_attention'] as List : const []))
        if (a is Map && _str(a['code']).isNotEmpty)
          PlanAttention(
            code: _str(a['code']),
            message: _str(a['message']),
            recordIds: [for (final id in (a['record_ids'] is List ? a['record_ids'] as List : const [])) _str(id)],
          ),
    ];
    final scope = _str(j['charge_scope']);
    return PlanDetail(
      id: _str(j['payment_id']),
      quoteNumber: _str(j['quotation_number']),
      quotationUuid: _str(j['quotation']),
      customerId: _str(customer?['customer_id']),
      customerName: _str(j['customer_name']).isNotEmpty ? _str(j['customer_name']) : _str(customer?['name']),
      leadId: _str(customer?['lead_id']),
      ptype: _str(j['payment_type']),
      status: _str(j['status']),
      total: total,
      paid: paid,
      balance: balance,
      totalInclGst: planNumOrNull(j['total_incl_gst']) ?? gross,
      amountDueInclGst: planNumOrNull(j['amount_due_incl_gst']) ?? grossDue,
      advanceReceived: planNumOrNull(j['advance_received']) ?? paid,
      invoicedTotal: planNum(j['invoiced_total']),
      quotedTotalInclGst: planNumOrNull(j['quoted_total_incl_gst']),
      unscheduledInclGst: planNumOrNull(j['unscheduled_incl_gst']),
      scheduleEditable: j['schedule_editable'] == true,
      numInstallments: (j['num_installments'] as num?)?.toInt(),
      billingPeriodDays: (j['billing_period_days'] as num?)?.toInt(),
      nextDueDate: _str(j['next_due_date']),
      needsAttention: attention,
      chargeScope: scope == 'one_time' || scope == 'recurring' ? scope : '',
      recurring: PlanRecurring.fromJson(j['recurring']),
      subscription: PlanSubscription.fromJson(j['subscription']),
      chargeSplit: PlanChargeSplit.fromJson(j['charge_split']),
      ownerName: ownerName,
      ownerEmail: _str(owner?['email']),
      amountCredited: planNum(j['amount_credited']),
      amountRefunded: planNum(j['amount_refunded']),
      records: records,
    );
  }
}

final RegExp _uuidLike = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

/// Whether [s] is a UUID — a plan route may carry the `payment_id` itself or a
/// display id (the quote number) that has to be resolved first.
bool isUuidLike(String s) => _uuidLike.hasMatch(s.trim());
