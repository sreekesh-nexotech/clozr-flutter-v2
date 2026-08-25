import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/view_schema.dart';
import '../../infrastructure/data_sources/remote/module_schema_remote_ds.dart';

/// Org-configured layouts for Customers, Quotes and Payments — the same
/// `/schema/?view_type=…` engine that already drives Leads, Tasks and
/// Follow-ups.
///
/// Every provider here follows the house contract: a `FutureProvider` doing the
/// fetch, and a synchronous `Provider` that answers [ViewSchema.empty] while it
/// is in flight, in mock mode, and on failure. Empty means "no opinion" — the
/// screen renders its built-in layout — so a list never waits behind a layout
/// call and never blanks because one failed.
///
/// Null in mock mode, which leaves every schema empty.
ModuleSchemaRemoteDataSource? _source(Ref ref, String schemaPath) {
  if (!ApiConfig.apiEnabled) return null;
  return ModuleSchemaRemoteDataSource(
    ref.watch(apiServiceProvider),
    schemaPath: schemaPath,
  );
}

// ── Customers ──

/// The customer card's layout: **mobile only, no `list` fallback**.
///
/// The customers list request asks for `?view_type=mobile` too, so the payload
/// is the org's mobile field set. Falling back to the list layout would show
/// slots the trimmed rows no longer carry.
final customerListSchemaFutureProvider = FutureProvider<ViewSchema>((ref) async {
  final ds = _source(ref, ApiEndpoints.customerSchema);
  return ds == null ? ViewSchema.empty : ds.fetchMobileSchema();
});

final customerListSchemaProvider = Provider<ViewSchema>((ref) =>
    ref.watch(customerListSchemaFutureProvider).valueOrNull ?? ViewSchema.empty);

final customerDetailSchemaFutureProvider =
    FutureProvider<ViewSchema>((ref) async {
  final ds = _source(ref, ApiEndpoints.customerSchema);
  return ds == null ? ViewSchema.empty : ds.fetchDetailSchema();
});

final customerDetailSchemaProvider = Provider<ViewSchema>((ref) =>
    ref.watch(customerDetailSchemaFutureProvider).valueOrNull ??
    ViewSchema.empty);

/// The raw customer record — the values the schema-driven panel renders.
final customerRowProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) async {
  if (id.isEmpty) return null;
  final ds = _source(ref, ApiEndpoints.customerSchema);
  return ds?.fetchRow(ApiEndpoints.customer(id));
});

// ── Quotes ──
//
// Note this is *not* `quoteSchemaProvider` in `quotes_providers.dart`. That one
// fetches `view_type=detail` to describe the **add-quote form** (deliberately,
// because `form` introspects model fields only and omits the ones the form
// needs). These two drive the list card and the detail panel.

final quoteListSchemaFutureProvider = FutureProvider<ViewSchema>((ref) async {
  final ds = _source(ref, ApiEndpoints.quotationSchema);
  return ds == null ? ViewSchema.empty : ds.fetchListSchema();
});

final quoteListSchemaProvider = Provider<ViewSchema>((ref) =>
    ref.watch(quoteListSchemaFutureProvider).valueOrNull ?? ViewSchema.empty);

final quoteDetailSchemaFutureProvider = FutureProvider<ViewSchema>((ref) async {
  final ds = _source(ref, ApiEndpoints.quotationSchema);
  return ds == null ? ViewSchema.empty : ds.fetchDetailSchema();
});

final quoteDetailSchemaProvider = Provider<ViewSchema>((ref) =>
    ref.watch(quoteDetailSchemaFutureProvider).valueOrNull ?? ViewSchema.empty);

final quoteRowProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) async {
  if (id.isEmpty) return null;
  final ds = _source(ref, ApiEndpoints.quotationSchema);
  return ds?.fetchRow(ApiEndpoints.quotation(id));
});

// ── Payments ──
//
// `model_name: payment` in the view-settings engine is the record at
// `/quotations/payments/` — which this app surfaces as an **invoice** (the
// header), with `/quotations/payment-records/` as the individual payments
// against it. So this schema drives the invoice card and invoice detail; the
// payment-record rows have no module of their own in the engine and keep their
// built-in layout.

final paymentListSchemaFutureProvider = FutureProvider<ViewSchema>((ref) async {
  final ds = _source(ref, ApiEndpoints.paymentSchema);
  return ds == null ? ViewSchema.empty : ds.fetchListSchema();
});

final paymentListSchemaProvider = Provider<ViewSchema>((ref) =>
    ref.watch(paymentListSchemaFutureProvider).valueOrNull ?? ViewSchema.empty);

final paymentDetailSchemaFutureProvider =
    FutureProvider<ViewSchema>((ref) async {
  final ds = _source(ref, ApiEndpoints.paymentSchema);
  return ds == null ? ViewSchema.empty : ds.fetchDetailSchema();
});

final paymentDetailSchemaProvider = Provider<ViewSchema>((ref) =>
    ref.watch(paymentDetailSchemaFutureProvider).valueOrNull ??
    ViewSchema.empty);

final paymentRowProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, id) async {
  if (id.isEmpty) return null;
  final ds = _source(ref, ApiEndpoints.paymentSchema);
  return ds?.fetchRow(ApiEndpoints.payment(id));
});

// ── Products ──
//
// Mobile only, no `list` fallback: the card's layout and the list payload
// describe the same field set, so borrowing the table layout would show slots
// the rows do not carry.

final productListSchemaFutureProvider = FutureProvider<ViewSchema>((ref) async {
  final ds = _source(ref, ApiEndpoints.productSchema);
  return ds == null ? ViewSchema.empty : ds.fetchMobileSchema();
});

final productListSchemaProvider = Provider<ViewSchema>((ref) =>
    ref.watch(productListSchemaFutureProvider).valueOrNull ?? ViewSchema.empty);
