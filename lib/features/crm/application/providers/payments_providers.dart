import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/payment.dart';
import '../../domain/repositories/payments_repository.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../../infrastructure/data_sources/local/payments_mock_ds.dart';
import '../../infrastructure/repositories/payments_repository_impl.dart';

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final paymentsRepositoryProvider = Provider<PaymentsRepository>(
  (ref) => const PaymentsRepositoryImpl(PaymentsMockDataSource()),
);

/// Async source of all payments.
final paymentsProvider = FutureProvider<List<Payment>>(
  (ref) => ref.watch(paymentsRepositoryProvider).getPayments(),
);

/// Look up a single payment by id (detail screen).
final paymentByIdProvider = Provider.family<Payment?, String>((ref, id) {
  final payments = ref.watch(paymentsProvider).valueOrNull;
  if (payments == null) return null;
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

/// Active saved-view chip keys (Collections risk / High value).
final paySavedProvider = StateProvider<Set<String>>((ref) => {});

/// Payments filtered by tab + saved views + search.
final visiblePaymentsProvider = Provider<List<Payment>>((ref) {
  final payments = ref.watch(paymentsProvider).valueOrNull ?? const [];
  final tab = ref.watch(payTabProvider);
  final saved = ref.watch(paySavedProvider);
  final q = ref.watch(paySearchProvider).trim().toLowerCase();

  Iterable<Payment> out = payments;
  if (tab != 'all') out = out.where((x) => x.status == tab);
  if (saved.contains('pod')) out = out.where((x) => x.status == 'overdue' || x.status == 'due');
  if (saved.contains('phv')) out = out.where((x) => x.amountNum >= 4000000);
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
