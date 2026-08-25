import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/customer.dart';
import '../../domain/repositories/customers_repository.dart';
import '../../infrastructure/data_sources/local/customers_mock_ds.dart';
import '../../infrastructure/data_sources/remote/customers_remote_ds.dart';
import '../../infrastructure/repositories/customers_api_repository.dart';
import '../../infrastructure/repositories/customers_repository_impl.dart';
import '../../../../core/filters/filter_models.dart';
import '../filters/customer_filter_codec.dart';
import '../filters/customers_filter_spec.dart';

/// DI seam: mock-backed by default; API-backed when a base URL is configured.
final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const CustomersRepositoryImpl(CustomersMockDataSource());
  }
  return CustomersApiRepository(
    CustomersRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// The query key for one customer fetch: the drawer's filters as server params.
///
/// A value type so Riverpod caches per distinct query — editing a filter
/// switches which instance is watched, which issues a request rather than
/// re-filtering rows already on screen. Mirrors `LeadListQuery`.
class CustomerListQuery {
  const CustomerListQuery({this.filters = const {}});

  final Map<String, dynamic> filters;

  String get signature {
    final keys = filters.keys.toList()..sort();
    return [for (final k in keys) '$k=${filters[k]}'].join('&');
  }

  @override
  bool operator ==(Object other) =>
      other is CustomerListQuery && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

/// Customers for one query — the server does the filtering.
final customersScopedProvider =
    FutureProvider.family<List<Customer>, CustomerListQuery>(
  (ref, q) => ref.watch(customersRepositoryProvider).getCustomers(filters: q.filters),
);

/// The server params a given drawer state produces.
///
/// Shared by [customerFilterParamsProvider] and by the screen, which needs to
/// build the *next* query key before it applies a filter. Both must agree
/// exactly, or the screen would invalidate a key the list never watches.
Map<String, dynamic> customerFilterParamsFor(
    FilterValues values, CustomerFilterCodec codec) {
  // Mock mode has no query engine behind it — the matcher runs locally there.
  if (!ApiConfig.apiEnabled || values.isEmpty) return const {};
  return codec.encode(values);
}

/// The drawer's filters as server params — the payload that makes `is not` mean
/// "not, anywhere in the org" instead of "not, among the rows we loaded".
final customerFilterParamsProvider = Provider<Map<String, dynamic>>(
  (ref) => customerFilterParamsFor(
    ref.watch(customerFiltersProvider),
    ref.watch(customerFilterCodecProvider),
  ),
);

/// Org-wide customers — the cross-screen lookup source. Follow-ups, quotes and
/// payments resolve a linked customer by id here, so this deliberately ignores
/// the list's drawer filters: narrowing it would blank out those links.
final customersProvider = FutureProvider<List<Customer>>(
  (ref) => ref.watch(customersScopedProvider(const CustomerListQuery()).future),
);

/// The Customers list itself, with the drawer filters resolved by the server.
final customersListProvider = FutureProvider<List<Customer>>(
  (ref) => ref.watch(
    customersScopedProvider(
      CustomerListQuery(filters: ref.watch(customerFilterParamsProvider)),
    ).future,
  ),
);

/// The same scope with the drawer filters dropped — backs the drawer's live
/// result preview, which must count against the whole scope.
final customersUnfilteredQueryProvider =
    Provider<CustomerListQuery>((ref) => const CustomerListQuery());

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

/// Customers added locally this session (from the Add customer sheet). Prepended
/// to the repo-backed list so new records appear immediately. Replace with a
/// write-through repository when the API lands.
final customerDraftsProvider = StateProvider<List<Customer>>((ref) => const []);

/// The full customer set: session-added drafts first, then the repo-backed list.
final customersAllProvider = Provider<List<Customer>>((ref) {
  // The **filtered** list: the drawer is resolved by the server in API mode, so
  // this is already the matching set. Tab counts therefore reflect the active
  // filters, which follows from filtering server-side.
  final repo = ref.watch(customersListProvider).valueOrNull ?? const [];
  final drafts = ref.watch(customerDraftsProvider);
  return [...drafts, ...repo];
});

/// Active status tab on the Customers list.
final customerTabProvider = StateProvider<String>((ref) => 'all');

/// Search query on the Customers list.
final customerSearchProvider = StateProvider<String>((ref) => '');

/// Whether the search field is expanded.
final customerSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Customers filtered by the active tab + search query + drawer filters.
final visibleCustomersProvider = Provider<List<Customer>>((ref) {
  final all = ref.watch(customersAllProvider);
  final tab = ref.watch(customerTabProvider);
  final q = ref.watch(customerSearchProvider).trim().toLowerCase();

  Iterable<Customer> out = all;
  if (tab != 'all') out = out.where((c) => c.status == tab);
  // Mock mode has no query engine behind it, so the drawer is matched here.
  // In API mode the server already ran it and re-filtering would be wrong: the
  // local matcher works off folded status keys and display names, not the ids
  // the server matched on.
  if (!ApiConfig.apiEnabled) {
    final filters = ref.watch(customerFiltersProvider);
    if (!filters.isEmpty) out = out.where((c) => customerMatchesFilters(c, filters));
  }
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
