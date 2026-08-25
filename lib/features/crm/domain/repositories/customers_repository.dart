import '../entities/customer.dart';

/// Abstract contract for customer data. The presentation layer depends only on
/// this; mock vs REST is an infrastructure detail.
abstract class CustomersRepository {
  /// [filters] are `/crm/customers/` query params from the drawer, applied
  /// **server-side** — so `is not` means "not, anywhere in the org" rather than
  /// "not, among the rows we happened to load".
  Future<List<Customer>> getCustomers({Map<String, dynamic> filters = const {}});

  /// Creates a customer from API-shaped form fields (`name`,
  /// `organization_name`, `email`, `phone`). Returns the created customer,
  /// or null when the backend response shape is unexpected.
  Future<Customer?> createCustomer(Map<String, dynamic> fields);

  /// Partial update — `PATCH /crm/customers/{id}/`. Used for the status pill,
  /// the owner (`assigned_to`) and the assignee set (`assignees`).
  Future<void> updateCustomer(String id, Map<String, dynamic> fields);

  /// Spawns an upsell lead against this customer and moves it into the
  /// `upsell_in_progress` status. Returns the new lead's id when the response
  /// carries one, so the caller can offer to open it.
  Future<String?> createUpsell(String id);

  /// The org's own customer statuses, in the order an admin arranged them.
  /// Empty in mock mode, which callers read as "use the built-in vocabulary".
  Future<List<CustomerStatus>> getCustomerStatuses();
}

/// One org-defined customer status.
///
/// [statusType] is the backend-fixed code (`active` / `upsell_in_progress` /
/// `completed` / `lost`) that decides the pill colour; [name] is free text an
/// admin can rename, so colour must never be derived from it.
class CustomerStatus {
  const CustomerStatus({
    required this.id,
    required this.name,
    required this.statusType,
  });

  final String id;
  final String name;
  final String statusType;
}
