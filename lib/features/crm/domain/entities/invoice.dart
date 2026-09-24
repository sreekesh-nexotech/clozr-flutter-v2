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
  final String type; // "Lump sum" | "Installments"
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
  });

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
