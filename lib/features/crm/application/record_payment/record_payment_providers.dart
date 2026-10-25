import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/network_providers.dart';
import '../../../../core/storage/app_cache.dart';
import '../../infrastructure/data_sources/remote/record_payment_remote_ds.dart';
import '../providers/invoices_providers.dart';
import '../providers/payments_providers.dart';
import 'record_payment_plan.dart';

final recordPaymentRemoteProvider = Provider<RecordPaymentRemoteDataSource>(
  (ref) => RecordPaymentRemoteDataSource(ref.watch(apiServiceProvider)),
);

/// The plan picker's results for one (already debounced) search term.
final recordPaymentPlanSearchProvider = FutureProvider.autoDispose.family<List<PlanOption>, String>(
  (ref, query) => ref.watch(recordPaymentRemoteProvider).searchPlans(query),
);

/// One plan with its records, keyed by `payment_id` (uuid).
final recordPaymentPlanProvider = FutureProvider.autoDispose.family<RecordPaymentPlan?, String>(
  (ref, planId) => planId.isEmpty ? Future.value(null) : ref.watch(recordPaymentRemoteProvider).getPlan(planId),
);

/// After a payment is recorded the server recalculates the plan (paid,
/// balance, completion, leftover cancellations), so every list and header
/// that shows it is stale. Pass `ref.invalidate`.
Future<void> invalidateAfterRecordPayment(void Function(ProviderOrFamily) invalidate, {String? planId}) async {
  // The offline copies too — otherwise a later network blip serves pre-payment rows.
  await AppCache.remove(AppCache.crmCache, 'payment_records');
  await AppCache.remove(AppCache.crmCache, 'invoices');
  invalidate(paymentsProvider);
  invalidate(invoicesProvider);
  invalidate(recordPaymentPlanSearchProvider);
  if (planId != null && planId.isNotEmpty) {
    invalidate(recordPaymentPlanProvider(planId));
  } else {
    invalidate(recordPaymentPlanProvider);
  }
}
