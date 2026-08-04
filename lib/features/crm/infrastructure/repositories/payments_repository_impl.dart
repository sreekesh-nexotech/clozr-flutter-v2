import '../../../../app/config/constants.dart';
import '../../domain/entities/payment.dart';
import '../../domain/repositories/payments_repository.dart';
import '../data_sources/local/payments_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one when the
/// API lands — the interface and every caller stay the same.
class PaymentsRepositoryImpl implements PaymentsRepository {
  const PaymentsRepositoryImpl(this._local);

  final PaymentsMockDataSource _local;

  @override
  Future<List<Payment>> getPayments() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchPayments();
  }

  @override
  Future<void> markRecordPaid(
    String recordId, {
    double? amount,
    String method = 'upi',
  }) async {
    // Mock mode: no backend — the sheet's local paid override is the state.
    await Future<void>.delayed(AppConstants.mockLatency);
  }
}
