import '../entities/payment.dart';

/// Abstract contract for payment data. The presentation layer depends only on
/// this; whether payments come from a mock source or a REST API is an
/// infrastructure detail.
abstract class PaymentsRepository {
  Future<List<Payment>> getPayments();

  /// Marks one installment record as settled ("settle" flow in the Record
  /// payment sheet). [amount] defaults server-side when omitted; [method] is
  /// the API code (`bank_transfer|upi|card|cash|cheque`). Mock mode is a
  /// no-op — the sheet applies its local paid override either way.
  Future<void> markRecordPaid(
    String recordId, {
    double? amount,
    String method = 'upi',
  });
}
