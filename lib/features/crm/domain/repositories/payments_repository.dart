import '../entities/payment.dart';

/// Abstract contract for payment data. The presentation layer depends only on
/// this; whether payments come from a mock source or a REST API is an
/// infrastructure detail.
abstract class PaymentsRepository {
  Future<List<Payment>> getPayments();
}
