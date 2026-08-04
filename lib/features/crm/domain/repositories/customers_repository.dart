import '../entities/customer.dart';

/// Abstract contract for customer data. The presentation layer depends only on
/// this; mock vs REST is an infrastructure detail.
abstract class CustomersRepository {
  Future<List<Customer>> getCustomers();

  /// Creates a customer from API-shaped form fields (`name`,
  /// `organization_name`, `email`, `phone`). Returns the created customer,
  /// or null when the backend response shape is unexpected.
  Future<Customer?> createCustomer(Map<String, dynamic> fields);
}
