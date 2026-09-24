import 'package:equatable/equatable.dart';

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
  });

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
      );

  @override
  List<Object?> get props => [id];
}
