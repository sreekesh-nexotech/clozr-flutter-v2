import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/repositories/invoices_repository.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../../infrastructure/data_sources/local/invoices_mock_ds.dart';
import '../../infrastructure/data_sources/remote/invoices_remote_ds.dart';
import '../../infrastructure/repositories/invoices_api_repository.dart';
import '../../infrastructure/repositories/invoices_repository_impl.dart';
import 'payments_providers.dart';

/// DI seam: mock-backed without a base URL, API-backed otherwise.
final invoicesRepositoryProvider = Provider<InvoicesRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const InvoicesRepositoryImpl(InvoicesMockDataSource());
  }
  return InvoicesApiRepository(
    InvoicesRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Async source of all invoices.
final invoicesProvider = FutureProvider<List<Invoice>>(
  (ref) => ref.watch(invoicesRepositoryProvider).getInvoices(),
);

/// Look up a single invoice by id (detail screen).
final invoiceByIdProvider = Provider.family<Invoice?, String>((ref, id) {
  final invoices = ref.watch(invoicesProvider).valueOrNull;
  if (invoices == null) return null;
  for (final iv in invoices) {
    if (iv.id == id) return iv;
  }
  return null;
});

/// Customer one-liner (company or name) for an invoice.
String invoiceWho(Invoice iv) =>
    CrmPartyDirectory.customer(iv.custId)?.company ??
    CrmPartyDirectory.customer(iv.custId)?.name ??
    iv.custId ??
    '—';

/// Customer contact person name for an invoice.
String invoiceContact(Invoice iv) => CrmPartyDirectory.customer(iv.custId)?.name ?? '';

// ── Invoices mode UI state (shares the Payments screen search field) ──
final invTabProvider = StateProvider<String>((ref) => 'all');

/// Invoices filtered by tab + the Payments-screen search query.
final visibleInvoicesProvider = Provider<List<Invoice>>((ref) {
  final invoices = ref.watch(invoicesProvider).valueOrNull ?? const [];
  final tab = ref.watch(invTabProvider);
  final q = ref.watch(paySearchProvider).trim().toLowerCase();

  Iterable<Invoice> out = invoices;
  if (tab != 'all') out = out.where((x) => x.status == tab);
  if (q.isNotEmpty) {
    out = out.where((x) => ('${x.id} ${invoiceWho(x)}').toLowerCase().contains(q));
  }
  return out.toList();
});

int invTabCount(List<Invoice> invoices, String key) {
  if (key == 'all') return invoices.length;
  return invoices.where((iv) => iv.status == key).length;
}
