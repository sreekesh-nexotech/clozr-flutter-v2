import 'package:equatable/equatable.dart';

/// `record_summary` on a payment record — what the accounting ledger made of
/// it (handover §9.1). Either half may be absent; the whole thing is null when
/// accounting is off *or* nothing is linked yet.
class RecordSummary extends Equatable {
  const RecordSummary({
    this.documentId,
    this.documentNumber,
    this.documentStatus,
    this.documentPaymentState,
    this.documentOpenBalance,
    this.receiptId,
    this.receiptStatus,
    this.receiptAmount,
    this.receiptDate,
    this.adjustmentState,
  });

  /// `adjustments.state` — what accounting did to the money after the fact
  /// (`RECEIPT_REVERSED | REFUNDED | PARTLY_REFUNDED | CREDITED |
  /// PARTLY_CREDITED`). Wins over "Paid" on the row's pill, as on web.
  final String? adjustmentState;

  final String? documentId;
  final String? documentNumber;
  final String? documentStatus;
  final String? documentPaymentState;
  final String? documentOpenBalance;
  final String? receiptId;
  final String? receiptStatus;
  final String? receiptAmount;
  final String? receiptDate;

  bool get hasDocument => documentId != null;
  bool get hasReceipt => receiptId != null;

  @override
  List<Object?> get props => [
        documentId, documentNumber, documentStatus, documentPaymentState,
        receiptId, receiptStatus, adjustmentState,
      ];
}

/// A CRM payment / installment. Fields mirror the prototype's `payments` seed
/// 1:1 so the mock data source maps directly and the shape is API-ready.
class Payment extends Equatable {
  final String id;
  final String? custId;

  /// The customer's display name, straight from the row.
  ///
  /// The payment-records serializer sends `customer_name` and no
  /// `customer_id`, so resolving by id produced an em dash on every row.
  final String? custName;
  final String? invId;

  /// The parent plan's `payment` UUID.
  ///
  /// The durable join key. `invoice_id` is deprecated and disappears one
  /// release after accounting ships, and `quotation_number` is absent whenever
  /// the source quote has no number — either way the schedule would silently
  /// come back empty.
  final String? planUuid;
  final String label; // e.g. "Advance (40%)"

  /// Display of [amountNum] — the **contracted** figure for this instalment.
  final String amount;

  /// The instalment's contracted amount in whole rupees.
  ///
  /// Deliberately the gross/expected figure, not the cash received. It used to
  /// switch to `amount_paid` once a record was paid, so an instalment settled
  /// with tax withheld showed the net cash beside a green "Paid" tick and the
  /// schedule rows no longer summed to the invoice total.
  final int amountNum;

  /// Cash actually received, in whole rupees. Equals [amountNum] unless
  /// something was deducted.
  final int paidCashNum;

  /// Tax withheld at source, in whole rupees. Counts toward settlement.
  final int tdsNum;

  /// GST withheld at source / collected at source, in whole rupees.
  final int gstTdsNum;
  final int gstTcsNum;

  /// Bank or gateway charge deducted from the receipt, in whole rupees.
  final int bankChargeNum;
  final String method; // "Bank transfer", "UPI", "—" …
  final String status; // key into StatusMeta$.payment
  final String date; // "05 May 2026" or "Overdue 24 Jun 2026"
  final String owner; // user id

  /// `amount_expected` exactly as sent (`"12500.50"`). [amountNum] rounds to
  /// whole rupees for the list's display; anything sent back to the server —
  /// the cash figure on mark-paid above all — is worked from this, or the
  /// paise are lost on the way to the ledger.
  final String amountExact;

  /// The ISSUED accounting invoice for this instalment, null until issued.
  final String? linkedDocumentId;

  /// The receipt the ledger posted when this record was marked paid.
  final String? postedReceiptId;
  final RecordSummary? recordSummary;

  /// `ADVANCE` / `CUSTOMER_CREDIT` — how an unlinked receipt was booked.
  final String? treatAs;
  final String? bankAccountId;
  final String? gatewayRef;

  // ── Webapp parity (payment list, PY-005) — every figure is the server's ──

  /// `installment_number`; 0 when absent.
  final int installmentNumber;

  /// `lead_name` — the deal's lead. Shown with a LEAD badge when the record
  /// has no customer yet (a quote accepted before its lead was converted).
  final String? leadName;

  /// `settlement_state`: `pending | partly_paid | paid`. "Paid" only once
  /// the balance is 0 — a record marked paid with GST still open is
  /// `partly_paid`. Derived from [status] when the server does not send it.
  final String settlementState;

  /// `amount_expected` / `amount_paid` with paise (the `*Num` ints round).
  final double amountExpected;
  final double amountPaid;

  /// `amount_due_incl_gst` — the row's MAIN figure: the linked tax invoice's
  /// total, else the quote's GST estimate, else the amount as quoted. Falls
  /// back to `amount_due_gross`, then [amountExpected].
  final double amountDueInclGst;

  /// `amount_due_basis`: `INVOICE | ESTIMATE | AS_QUOTED`; null on an older
  /// backend.
  final String? amountDueBasis;

  /// `balance_due` — the open gross balance.
  final double balanceDue;

  /// `due_date` / `paid_date` as calendar days.
  final DateTime? dueOn;
  final DateTime? paidOn;

  /// `payment_method` exactly as sent (`bank_transfer`, …); null when unset.
  final String? methodCode;

  /// `invoice_blocked_reason` (`CUSTOMER_REQUIRED`), `cancel_reason`.
  final String? invoiceBlockedReason;
  final String? cancelReason;

  const Payment({
    required this.id,
    required this.custId,
    this.custName,
    required this.invId,
    this.planUuid,
    required this.label,
    required this.amount,
    required this.amountNum,
    required this.method,
    required this.status,
    required this.date,
    required this.owner,
    this.paidCashNum = 0,
    this.tdsNum = 0,
    this.gstTdsNum = 0,
    this.gstTcsNum = 0,
    this.bankChargeNum = 0,
    this.amountExact = '',
    this.linkedDocumentId,
    this.postedReceiptId,
    this.recordSummary,
    this.treatAs,
    this.bankAccountId,
    this.gatewayRef,
    this.installmentNumber = 0,
    this.leadName,
    this.settlementState = 'pending',
    this.amountExpected = 0,
    this.amountPaid = 0,
    this.amountDueInclGst = 0,
    this.amountDueBasis,
    this.balanceDue = 0,
    this.dueOn,
    this.paidOn,
    this.methodCode,
    this.invoiceBlockedReason,
    this.cancelReason,
  });

  /// The server cancelled this record (plan closed, credited, …).
  bool get isCancelled => status == 'cancelled';

  /// Accounting issued a tax document for it — it settles through that
  /// document and can be neither deleted nor auto-cancelled.
  bool get isLinkedToDocument =>
      linkedDocumentId != null || recordSummary?.documentId != null;

  /// No customer yet: the row names the lead instead, with a LEAD badge.
  bool get isLeadOnly =>
      (custName == null || custName!.isEmpty) && (leadName ?? '').isNotEmpty;

  /// Everything deducted from the contracted amount before cash arrived.
  int get deductionsNum => tdsNum + gstTdsNum + gstTcsNum + bankChargeNum;

  /// Whether this record was settled with anything withheld — the only case
  /// where cash received and the contracted amount differ.
  bool get hasDeductions => deductionsNum > 0;

  /// A copy with selected fields replaced.
  ///
  /// Added because [allPaymentsProvider] rebuilt `Payment` field by field for
  /// its optimistic paid-override; every field added here had to be remembered
  /// there or it silently reset to its default on settle.
  Payment copyWith({
    String? status,
    String? date,
    String? method,
    int? paidCashNum,
    String? settlementState,
    DateTime? paidOn,
  }) =>
      Payment(
        id: id,
        custId: custId,
        custName: custName,
        invId: invId,
        planUuid: planUuid,
        label: label,
        amount: amount,
        amountNum: amountNum,
        method: method ?? this.method,
        status: status ?? this.status,
        date: date ?? this.date,
        owner: owner,
        paidCashNum: paidCashNum ?? this.paidCashNum,
        tdsNum: tdsNum,
        gstTdsNum: gstTdsNum,
        gstTcsNum: gstTcsNum,
        bankChargeNum: bankChargeNum,
        amountExact: amountExact,
        linkedDocumentId: linkedDocumentId,
        postedReceiptId: postedReceiptId,
        recordSummary: recordSummary,
        treatAs: treatAs,
        bankAccountId: bankAccountId,
        gatewayRef: gatewayRef,
        installmentNumber: installmentNumber,
        leadName: leadName,
        settlementState: settlementState ?? this.settlementState,
        amountExpected: amountExpected,
        amountPaid: amountPaid,
        amountDueInclGst: amountDueInclGst,
        amountDueBasis: amountDueBasis,
        balanceDue: balanceDue,
        dueOn: dueOn,
        paidOn: paidOn ?? this.paidOn,
        methodCode: methodCode,
        invoiceBlockedReason: invoiceBlockedReason,
        cancelReason: cancelReason,
      );

  @override
  List<Object?> get props => [id];
}

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The webapp's canonical calendar day, `DD-MON-YYYY` (`05-Oct-2026`). A
/// date-only value is a calendar day, so no time-zone shift is applied.
String dayMonYear(DateTime? d) =>
    d == null ? '' : '${d.day.toString().padLeft(2, '0')}-${_mon[d.month - 1]}-${d.year}';

/// Webapp `rowDate`: a paid record shows its paid date, an overdue one
/// "Overdue <due>", a pending one "Due <due>", a cancelled one its due date;
/// an em dash when the date it needs is missing.
String paymentRowDate({required String status, DateTime? dueOn, DateTime? paidOn}) {
  if (status == 'paid') return paidOn == null ? '—' : dayMonYear(paidOn);
  if (dueOn == null) return '—';
  final d = dayMonYear(dueOn);
  if (status == 'overdue') return 'Overdue $d';
  if (status == 'due' || status == 'scheduled') return 'Due $d';
  return d;
}
