import '../entities/payment.dart';

/// Abstract contract for payment data. The presentation layer depends only on
/// this; whether payments come from a mock source or a REST API is an
/// infrastructure detail.
abstract class PaymentsRepository {
  Future<List<Payment>> getPayments();

  /// Marks one installment record as settled. [amountPaid] is the cash
  /// received as a decimal string (defaults server-side when omitted);
  /// [method] is the API code (`bank_transfer|upi|card|cash|cheque`). The
  /// accounting fields follow handover §9.1. Returns whether the ledger posted
  /// a receipt. Mock mode is a no-op — the sheet's local override is the state.
  Future<bool> markRecordPaid(
    String recordId, {
    String? amountPaid,
    String method = 'upi',
    DateTime? paidDate,
    String? tdsDeducted,
    String? bankCharge,
    String? bankAccountId,
    String? treatAs,
    String? gatewayRef,
  });

  /// Deletes one record (`DELETE payment-records/{id}/`) — only an unpaid,
  /// uninvoiced record on a milestone-based plan; the server recalculates
  /// the plan's totals and refuses anything else with its reason.
  Future<void> deleteRecord(String recordId);
}
