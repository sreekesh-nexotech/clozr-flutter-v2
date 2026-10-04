import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/acc_masters.dart';
import '../../domain/entities/acc_settlement.dart';
import 'accounting_providers.dart';

/// A party filter for the settlement lists: `null` lists every party.
typedef PartyKey = String?;

final receiptsProvider = FutureProvider.autoDispose.family<List<AccReceipt>, PartyKey>(
  (ref, customer) => ref.watch(accountingRepositoryProvider).receipts(customer: customer),
);

/// The full receipt with its allocations — the detail read.
final receiptDetailProvider = FutureProvider.autoDispose.family<AccReceipt?, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).receipt(id),
);

final advancesProvider = FutureProvider.autoDispose.family<List<AccAdvance>, PartyKey>(
  (ref, customer) => ref.watch(accountingRepositoryProvider).advances(customer: customer),
);

final customerCreditsProvider = FutureProvider.autoDispose.family<List<AccCustomerCredit>, PartyKey>(
  (ref, customer) => ref.watch(accountingRepositoryProvider).customerCredits(customer: customer),
);

final vendorPaymentsProvider = FutureProvider.autoDispose.family<List<AccVendorPayment>, PartyKey>(
  (ref, vendor) => ref.watch(accountingRepositoryProvider).vendorPayments(vendor: vendor),
);

final vendorPaymentDetailProvider = FutureProvider.autoDispose.family<AccVendorPayment?, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).vendorPayment(id),
);

final vendorAdvancesProvider = FutureProvider.autoDispose.family<List<AccVendorAdvance>, PartyKey>(
  (ref, vendor) => ref.watch(accountingRepositoryProvider).vendorAdvances(vendor: vendor),
);

/// Every active vendor, for pickers and for resolving vendor names on rows —
/// document and settlement rows carry ids only (§12.5).
final vendorsProvider = FutureProvider<List<Vendor>>(
  (ref) => ref.watch(accountingRepositoryProvider).vendors(),
);

/// `vendor_id → name`, empty until [vendorsProvider] lands.
final vendorNameProvider = Provider<String? Function(String?)>((ref) {
  final vendors = ref.watch(vendorsProvider).valueOrNull ?? const [];
  final byId = {for (final v in vendors) v.id: v.name};
  return (id) => id == null ? null : byId[id];
});

final vendorDetailProvider = FutureProvider.autoDispose.family<Vendor?, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).vendor(id),
);

/// A customer's or vendor's tax profile — `(kind, id)`.
final partyTaxProfileProvider =
    FutureProvider.autoDispose.family<PartyTaxProfile, ({String kind, String id})>(
  (ref, key) => ref.watch(accountingRepositoryProvider).partyTaxProfile(key.kind, key.id),
);

final productTaxProfileProvider = FutureProvider.autoDispose.family<ProductTaxProfile, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).productTaxProfile(id),
);
