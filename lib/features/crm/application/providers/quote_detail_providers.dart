import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../infrastructure/data_sources/remote/quote_actions_remote_ds.dart';
import '../quote_lifecycle.dart';

/// The quote detail's lifecycle endpoints.
final quoteActionsDsProvider =
    Provider<QuoteActionsRemoteDataSource>((ref) => QuoteActionsRemoteDataSource(ref.watch(apiServiceProvider)));

/// The org's quote statuses with their meaning (`status_type`), inactive rows
/// included — the lifecycle rules and the status picker read these.
final quoteLifecycleStatusesProvider = FutureProvider<List<QuoteStatusRow>>((ref) async {
  if (!ApiConfig.apiEnabled) return const [];
  try {
    return await ref.watch(quoteActionsDsProvider).statuses();
  } on Object {
    return const [];
  }
});

/// Active decline reasons for the "Why was this quote declined?" dialog.
final quoteDeclineReasonsProvider =
    FutureProvider.autoDispose<List<({String id, String name})>>((ref) => ref.watch(quoteActionsDsProvider).declineReasons());

/// `GET {id}/payment-instructions/` — null when none are set up.
final quotePaymentInstructionsProvider =
    FutureProvider.autoDispose.family<QuotePaymentInstructions?, String>((ref, id) async {
  if (id.isEmpty || !ApiConfig.apiEnabled) return null;
  return ref.watch(quoteActionsDsProvider).paymentInstructions(id);
});

/// The newest revision of a superseded quote's chain (`quotation_id`,
/// `quotation_number`), or null. Keyed by `uuid|number|revisionNo`.
final quoteLatestRevisionProvider =
    FutureProvider.autoDispose.family<({String id, String number})?, String>((ref, key) async {
  final parts = key.split('|');
  if (parts.length < 3 || parts[1].isEmpty) return null;
  final facts = QuoteFacts(id: parts[0], number: parts[1], revisionNo: int.tryParse(parts[2]) ?? 0);
  try {
    final rows = await ref.watch(quoteActionsDsProvider).searchQuotes(baseQuoteNumber(facts.number));
    final best = pickLatestRevision(rows, facts);
    if (best == null) return null;
    return (id: '${best['quotation_id'] ?? ''}', number: '${best['quotation_number'] ?? ''}');
  } on Object {
    return null;
  }
});

/// A lead's `reference` ("LD-0025"), '' when unknown.
final quoteLeadReferenceProvider = FutureProvider.autoDispose.family<String, String>((ref, leadId) async {
  if (leadId.isEmpty || !ApiConfig.apiEnabled) return '';
  return ref.watch(quoteActionsDsProvider).reference(ApiEndpoints.lead(leadId));
});

/// A customer's `reference` ("CUST-0002"), '' when unknown.
final quoteCustomerReferenceProvider = FutureProvider.autoDispose.family<String, String>((ref, customerId) async {
  if (customerId.isEmpty || !ApiConfig.apiEnabled) return '';
  return ref.watch(quoteActionsDsProvider).reference(ApiEndpoints.customer(customerId));
});

/// The org's document templates for "Generate document".
final quoteDocTemplatesProvider =
    FutureProvider.autoDispose<List<DocTemplate>>((ref) => ref.watch(quoteActionsDsProvider).documentTemplates());

/// Whether the role may export quotes (`can_export`, read straight off
/// `/auth/me/modules/`; open while unknown, like every other gate).
final quoteCanExportProvider = Provider<bool>((ref) {
  final access = ref.watch(moduleAccessProvider).valueOrNull;
  if (access == null) return true;
  return access.modules['quotation']?.canExport ?? false;
});

const kExportDenied = "You don't have permission to export from here. Ask a workspace admin.";

/// Why the quote record could not be read (null when it can be) — tells the
/// detail screen "Quote not found" (404) from "Couldn't load this quote".
final quoteLoadErrorProvider = FutureProvider.autoDispose.family<AppError?, String>((ref, id) async {
  if (id.isEmpty || !ApiConfig.apiEnabled) return null;
  try {
    await ref.read(apiServiceProvider).get(ApiEndpoints.quotation(id), quiet: true);
    return null;
  } on AppError catch (e) {
    return e;
  } on Object catch (e) {
    return AppError(type: AppErrorType.unknown, message: '$e');
  }
});
