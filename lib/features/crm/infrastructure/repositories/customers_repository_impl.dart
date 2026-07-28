import '../../../../app/config/constants.dart';
import '../../domain/entities/customer.dart';
import '../../domain/repositories/customers_repository.dart';
import '../data_sources/local/customers_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one when the
/// API lands — the interface and every caller stay the same.
class CustomersRepositoryImpl implements CustomersRepository {
  const CustomersRepositoryImpl(this._local);

  final CustomersMockDataSource _local;

  @override
  Future<List<Customer>> getCustomers() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchCustomers();
  }
}
