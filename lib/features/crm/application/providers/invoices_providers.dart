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
import 'crm_party_providers.dart';
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

/// The server's totals for one invoice, keyed by `payment_id`.
///
/// Refetched off the write tick, because settling a record recalculates the
/// parent — `amount_paid`, `next_due_date` and completion all move server-side
/// (see `markRecordPaid`'s note), and the whole point of this call is to show
/// the server's numbers rather than guess at them.
///
/// `autoDispose` so a session's worth of opened invoices does not keep
/// refetching on every write anywhere.
final invoiceSummaryProvider =
    FutureProvider.autoDispose.family<InvoiceSummary?, String>((ref, paymentId) {
  if (paymentId.isEmpty) return Future.value(null);
  ref.watch(apiWriteTickProvider);
  return ref.watch(invoicesRepositoryProvider).getInvoiceSummary(paymentId);
});

/// Look up a single invoice by id (detail screen).
final invoiceByIdProvider = Provider.family<Invoice?, String>((ref, id) {
  final invoices = ref.watch(invoicesProvider).valueOrNull;
  if (invoices == null) return null;
  for (final iv in invoices) {
    if (iv.id == id) return iv;
  }
  return null;
});

/// Customer one-liner (company or name) for an invoice, resolved via [lookup]
/// (real customers in API mode, the seed directory in mock mode). Falls back to
/// the raw `custId` / em-dash when the party is unknown.
String invoiceWho(Invoice iv, CrmPartyLookup lookup) {
  final party = lookup(custId: iv.custId);
  final company = party?.company;
  if (company != null && company.isNotEmpty) return company;
  final name = party?.name;
  if (name != null && name.isNotEmpty) return name;
  return iv.custId ?? '—';
}

/// Customer contact person name for an invoice, resolved via [lookup].
String invoiceContact(Invoice iv, CrmPartyLookup lookup) =>
    lookup(custId: iv.custId)?.name ?? '';

// ── Invoices mode UI state (shares the Payments screen search field) ──
final invTabProvider = StateProvider<String>((ref) => 'all');

/// Invoices filtered by tab + the Payments-screen search query.
final visibleInvoicesProvider = Provider<List<Invoice>>((ref) {
  final invoices = ref.watch(invoicesProvider).valueOrNull ?? const [];
  final tab = ref.watch(invTabProvider);
  final q = ref.watch(paySearchProvider).trim().toLowerCase();
  final lookup = ref.watch(crmPartyLookupProvider);

  Iterable<Invoice> out = invoices;
  if (tab != 'all') out = out.where((x) => x.status == tab);
  if (q.isNotEmpty) {
    out = out.where((x) => ('${x.id} ${invoiceWho(x, lookup)}').toLowerCase().contains(q));
  }
  return out.toList();
});

int invTabCount(List<Invoice> invoices, String key) {
  if (key == 'all') return invoices.length;
  return invoices.where((iv) => iv.status == key).length;
}
