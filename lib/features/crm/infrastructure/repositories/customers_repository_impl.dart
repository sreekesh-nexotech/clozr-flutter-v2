import '../../../../app/config/constants.dart';
import '../../../../data/api/user_directory.dart';
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

  /// Local echo — mock mode has no backend, so the "created" customer is
  /// built from the submitted fields, mirroring what the Add customer sheet
  /// builds today (never persisted; mock behavior unchanged).
  @override
  Future<Customer?> createCustomer(Map<String, dynamic> fields) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    final name = (fields['name'] ?? '').toString();
    return Customer(
      id: 'C${DateTime.now().millisecondsSinceEpoch.remainder(100000)}',
      leadId: null,
      name: name,
      initials: UserDirectory.initialsOf(name),
      company: (fields['organization_name'] ?? '').toString(),
      project: 'New engagement',
      value: '—',
      valueNum: 0,
      status: 'active',
      since: '',
      statusDays: 0,
      score: 70,
      source: 'Referral',
      owner: 'me',
      team: const ['me'],
      phone: (fields['phone'] ?? '').toString(),
      email: (fields['email'] ?? '').toString(),
      website: '',
      industry: '—',
      location: '—',
      createdOn: '',
      time: 'Just now',
      lastFu: 'Customer created manually.',
      notif: 0,
    );
  }
}
