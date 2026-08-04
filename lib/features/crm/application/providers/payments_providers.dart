import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/payment.dart';
import '../../domain/repositories/payments_repository.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../../infrastructure/data_sources/local/payments_mock_ds.dart';
import '../../infrastructure/data_sources/remote/payments_remote_ds.dart';
import '../../infrastructure/repositories/payments_api_repository.dart';
import '../../infrastructure/repositories/payments_repository_impl.dart';
import '../filters/payments_filter_spec.dart';

/// DI seam: mock-backed without a base URL, API-backed otherwise.
final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const PaymentsRepositoryImpl(PaymentsMockDataSource());
  }
  return PaymentsApiRepository(
    PaymentsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Async source of all payments.
final paymentsProvider = FutureProvider<List<Payment>>(
  (ref) => ref.watch(paymentsRepositoryProvider).getPayments(),
);

/// Payments recorded in-session via the "Record payment" sheet (#14). Prepended
/// to the seed list; replaced by the API on integration.
final manualPaymentsProvider = StateProvider<List<Payment>>((ref) => const []);

/// Ids of seed installments marked paid in-session (the "settle" flow). Applied
/// as a status override on top of the seed data.
final paidOverrideProvider = StateProvider<Set<String>>((ref) => const {});

/// All payments = session additions + seed data, with in-session "settle"
/// overrides applied. The single source the list and drawer read from.
final allPaymentsProvider = Provider<List<Payment>>((ref) {
  final seed = ref.watch(paymentsProvider).valueOrNull ?? const [];
  final manual = ref.watch(manualPaymentsProvider);
  final paid = ref.watch(paidOverrideProvider);
  final resolved = [
    for (final p in seed)
      if (paid.contains(p.id) && p.status != 'paid')
        Payment(
          id: p.id,
          custId: p.custId,
          invId: p.invId,
          label: p.label,
          amount: p.amount,
          amountNum: p.amountNum,
          method: p.method,
          status: 'paid',
          date: p.date,
          owner: p.owner,
        )
      else
        p,
  ];
  return [...manual, ...resolved];
});

/// Look up a single payment by id (detail screen).
final paymentByIdProvider = Provider.family<Payment?, String>((ref, id) {
  final payments = ref.watch(allPaymentsProvider);
  for (final p in payments) {
    if (p.id == id) return p;
  }
  return null;
});

/// All payments belonging to an invoice (invoice detail schedule).
final paymentsForInvoiceProvider = Provider.family<List<Payment>, String>((ref, invId) {
  final payments = ref.watch(paymentsProvider).valueOrNull ?? const [];
  return payments.where((p) => p.invId == invId).toList();
});

/// Customer/lead one-liner (company or name) for a payment.
String paymentTitle(Payment p) =>
    CrmPartyDirectory.customer(p.custId)?.company ??
    CrmPartyDirectory.customer(p.custId)?.name ??
    p.custId ??
    '—';

/// The prototype's `PAYMETHOD` icon map.
IconData payMethodIcon(String method) {
  switch (method) {
    case 'Bank transfer':
      return PhosphorIconsRegular.bank;
    case 'Cheque':
      return PhosphorIconsRegular.note;
    case 'UPI':
      return PhosphorIconsRegular.deviceMobile;
    case 'Auto-debit':
      return PhosphorIconsRegular.arrowsClockwise;
    default:
      return PhosphorIconsRegular.clock;
  }
}

/// Colour used for a payment's date line by status.
Color paymentDateColor(String status) {
  switch (status) {
    case 'overdue':
      return AppColors.error;
    case 'due':
      return AppColors.warningDeep;
    case 'scheduled':
      return AppColors.blueBright;
    default:
      return AppColors.success;
  }
}

// ── Payments screen UI state ──

/// Mode toggle on the Payments screen: 'payments' | 'invoices'.
final payModeProvider = StateProvider<String>((ref) => 'payments');
final payTabProvider = StateProvider<String>((ref) => 'all');
final paySearchProvider = StateProvider<String>((ref) => '');
final paySearchOpenProvider = StateProvider<bool>((ref) => false);

/// Payments filtered by tab + drawer filters + search.
final visiblePaymentsProvider = Provider<List<Payment>>((ref) {
  final payments = ref.watch(allPaymentsProvider);
  final tab = ref.watch(payTabProvider);
  final filters = ref.watch(paymentFiltersProvider);
  final q = ref.watch(paySearchProvider).trim().toLowerCase();

  Iterable<Payment> out = payments;
  if (tab != 'all') out = out.where((x) => x.status == tab);
  if (!filters.isEmpty) out = out.where((x) => paymentMatchesFilters(x, filters));
  if (q.isNotEmpty) {
    out = out.where((x) =>
        ('${x.id} ${paymentTitle(x)} ${x.invId ?? ''}').toLowerCase().contains(q));
  }
  return out.toList();
});

int payTabCount(List<Payment> payments, String key) {
  if (key == 'all') return payments.length;
  return payments.where((p) => p.status == key).length;
}
