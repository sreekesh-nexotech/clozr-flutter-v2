import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/customer.dart';
import '../../domain/repositories/customers_repository.dart';
import '../../infrastructure/data_sources/local/customers_mock_ds.dart';
import '../../infrastructure/repositories/customers_repository_impl.dart';

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => const CustomersRepositoryImpl(CustomersMockDataSource()),
);

/// Async source of all customers.
final customersProvider = FutureProvider<List<Customer>>(
  (ref) => ref.watch(customersRepositoryProvider).getCustomers(),
);

/// Look up a single customer by id (used by the detail screen).
final customerByIdProvider = Provider.family<Customer?, String>((ref, id) {
  final customers = ref.watch(customersProvider).valueOrNull;
  if (customers == null) return null;
  for (final c in customers) {
    if (c.id == id) return c;
  }
  return null;
});

// ── List UI state ──

/// Active status tab on the Customers list.
final customerTabProvider = StateProvider<String>((ref) => 'all');

/// Search query on the Customers list.
final customerSearchProvider = StateProvider<String>((ref) => '');

/// Whether the search field is expanded.
final customerSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Customers filtered by the active tab + search query.
final visibleCustomersProvider = Provider<List<Customer>>((ref) {
  final all = ref.watch(customersProvider).valueOrNull ?? const [];
  final tab = ref.watch(customerTabProvider);
  final q = ref.watch(customerSearchProvider).trim().toLowerCase();

  Iterable<Customer> out = all;
  if (tab != 'all') out = out.where((c) => c.status == tab);
  if (q.isNotEmpty) {
    out = out.where((c) =>
        c.name.toLowerCase().contains(q) ||
        (c.company ?? '').toLowerCase().contains(q) ||
        c.id.toLowerCase().contains(q));
  }
  return out.toList();
});

/// Count of customers for a given tab key.
int customerTabCount(List<Customer> all, String key) {
  if (key == 'all') return all.length;
  return all.where((c) => c.status == key).length;
}
