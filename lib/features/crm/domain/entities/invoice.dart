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
    required this.quoteId,
    this.quoteUuid,
    required this.type,
    required this.total,
    required this.totalNum,
    required this.settled,
    required this.of,
    required this.balance,
    this.paidNum = 0,
    required this.status,
  });

  /// Fraction of installments settled (0..1).
  double get progress => of == 0 ? 0 : settled / of;

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

  @override
  List<Object?> get props => [
        totalNum, paidNum, remainingNum, currency, status,
        nextDue, totalRecords, pendingRecords, paidRecords, overdueRecords,
      ];
}
