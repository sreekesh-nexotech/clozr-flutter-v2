import '../../../../app/config/constants.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/repositories/invoices_repository.dart';
import '../data_sources/local/invoices_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one when the
/// API lands — the interface and every caller stay the same.
class InvoicesRepositoryImpl implements InvoicesRepository {
  const InvoicesRepositoryImpl(this._local);

  final InvoicesMockDataSource _local;

  @override
  Future<List<Invoice>> getInvoices() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchInvoices();
  }
}
