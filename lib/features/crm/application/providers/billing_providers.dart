import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/app_error.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/billing.dart';
import '../../infrastructure/data_sources/remote/billing_remote_ds.dart';

/// The billing reads. Null data source in mock mode, where the screen keeps the
/// prototype's static cards — there is nothing to read from.
final billingRemoteDataSourceProvider = Provider<BillingRemoteDataSource?>((ref) {
  if (!ApiConfig.apiEnabled) return null;
  return BillingRemoteDataSource(ref.watch(apiServiceProvider));
});

/// `GET /billing/invoices/` — the billing history.
final billingInvoicesProvider = FutureProvider<List<BillingInvoice>>((ref) async {
  final ds = ref.watch(billingRemoteDataSourceProvider);
  if (ds == null) return const [];
  return ds.fetchInvoices();
});

/// `GET /billing/storage/` — the storage card.
final billingStorageProvider = FutureProvider<StorageUsage?>((ref) async {
  final ds = ref.watch(billingRemoteDataSourceProvider);
  if (ds == null) return null;
  return ds.fetchStorage();
});

/// `GET /billing/subscriptions/` — the plan header. Null when unreadable or
/// absent, and the screen leaves the header out rather than inventing one.
final billingSubscriptionProvider = FutureProvider<BillingSubscription?>((ref) async {
  final ds = ref.watch(billingRemoteDataSourceProvider);
  if (ds == null) return null;
  try {
    return await ds.fetchSubscription();
  } on AppError {
    return null;
  }
});

/// `GET /billing/plans/` — what the Change-plan sheet lists.
final billingPlansProvider = FutureProvider<List<BillingPlan>>((ref) async {
  final ds = ref.watch(billingRemoteDataSourceProvider);
  if (ds == null) return const [];
  return ds.fetchPlans();
});
