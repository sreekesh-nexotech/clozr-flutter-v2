import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../infrastructure/data_sources/remote/payment_plan_remote_ds.dart';
import '../payment_plan/payment_plan_detail.dart';

final paymentPlanRemoteProvider = Provider<PaymentPlanRemoteDataSource>(
  (ref) => PaymentPlanRemoteDataSource(ref.watch(apiServiceProvider)),
);

/// One payment plan with its records, keyed by `payment_id`.
///
/// Refetched off the write tick: settling, re-splitting or adding a milestone
/// recalculates the plan server-side. The screen renders its own not-found /
/// load-error state, so the failure is withdrawn from the shell toast.
final paymentPlanDetailProvider = FutureProvider.autoDispose.family<PlanDetail, String>((ref, planId) async {
  ref.watch(apiWriteTickProvider);
  try {
    return await ref.read(paymentPlanRemoteProvider).getPlan(planId);
  } on AppError catch (e) {
    ref.read(apiServiceProvider).handled(e);
    rethrow;
  }
});

/// One payment record, keyed by `record_id`. Same refresh / error rules.
final paymentRecordDetailProvider = FutureProvider.autoDispose.family<PlanRecord, String>((ref, recordId) async {
  ref.watch(apiWriteTickProvider);
  try {
    return await ref.read(paymentPlanRemoteProvider).getRecord(recordId);
  } on AppError catch (e) {
    ref.read(apiServiceProvider).handled(e);
    rethrow;
  }
});

/// The lead behind a lead-only plan, read off its quote. '' when unknown.
final planQuoteLeadIdProvider = FutureProvider.autoDispose.family<String, String>((ref, quotationId) async {
  if (quotationId.isEmpty) return '';
  try {
    return await ref.read(paymentPlanRemoteProvider).getQuoteLeadId(quotationId);
  } on AppError {
    return '';
  }
});
