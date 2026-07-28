import '../entities/customer.dart';

/// Abstract contract for customer data. The presentation layer depends only on
/// this; mock vs REST is an infrastructure detail.
abstract class CustomersRepository {
  Future<List<Customer>> getCustomers();
}
