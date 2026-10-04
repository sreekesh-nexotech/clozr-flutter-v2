import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../domain/entities/acc_document.dart';
import '../../../domain/entities/acc_settlement.dart';
import 'acc_remote_support.dart';
import 'accounting_mappers.dart';

/// Money in and money out (`/accounting/settlement/…` and
/// `/accounting/purchases/…`, handover §8.4–8.5).
///
/// Every write here posts to the ledger immediately, carries the caller's
/// `event_id`, and may come back `{skipped: true}` — see [PostOutcome].
class AccountingSettlementRemoteDataSource {
  const AccountingSettlementRemoteDataSource(this._api);

  final ApiService _api;

  Future<RawPage> _list(String path, Map<String, Object?> filters, int page) async {
    final res = await _api.get(path, query: compact({...filters, 'page': page, 'page_size': 50}));
    return RawPage.from(res);
  }

  // ── Receipts ──

  Future<RawPage> fetchReceipts({String? customer, String? status, int page = 1}) =>
      _list(ApiEndpoints.accReceipts, {'customer': customer, 'status': status}, page);

  Future<AccReceipt?> fetchReceipt(String id) async {
    final res = await _api.get(ApiEndpoints.accReceipt(id));
    return res is Map ? mapReceipt(Map<String, dynamic>.from(res)) : null;
  }

  Future<PostOutcome<AccReceipt>> recordReceipt(Map<String, Object?> body) async {
    final res = await _api.post(ApiEndpoints.accReceipts, body: compact(body));
    return postOutcome(res, mapReceipt);
  }

  Future<PostOutcome<String>> reverseReceipt(String id, {String? reason, required String eventId}) async {
    final res = await _api.post(ApiEndpoints.accReceiptReverse(id),
        body: compact({'reason': reason, 'event_id': eventId}));
    return postOutcome(res, (m) => m['entry_id']?.toString());
  }

  // ── Advances & credits ──

  Future<RawPage> fetchAdvances({String? customer, String? status, int page = 1}) =>
      _list(ApiEndpoints.accAdvances, {'customer': customer, 'status': status}, page);

  /// Returns the **receipt** row, not the advance (§12.12).
  Future<PostOutcome<AccReceipt>> recordAdvance(Map<String, Object?> body) async {
    final res = await _api.post(ApiEndpoints.accAdvances, body: compact(body));
    return postOutcome(res, mapReceipt);
  }

  Future<RawPage> fetchCustomerCredits({String? customer, String? status, int page = 1}) =>
      _list(ApiEndpoints.accCustomerCredits, {'customer': customer, 'status': status}, page);

  // ── Vendor payments & advances ──

  Future<RawPage> fetchVendorPayments({String? vendor, String? status, int page = 1}) =>
      _list(ApiEndpoints.accVendorPayments, {'vendor': vendor, 'status': status}, page);

  Future<AccVendorPayment?> fetchVendorPayment(String id) async {
    final res = await _api.get(ApiEndpoints.accVendorPayment(id));
    return res is Map ? mapVendorPayment(Map<String, dynamic>.from(res)) : null;
  }

  Future<PostOutcome<AccVendorPayment>> recordVendorPayment(Map<String, Object?> body) async {
    final res = await _api.post(ApiEndpoints.accVendorPayments, body: compact(body));
    return postOutcome(res, mapVendorPayment);
  }

  Future<PostOutcome<String>> reverseVendorPayment(String id, {required String eventId}) async {
    final res = await _api.post(ApiEndpoints.accVendorPaymentReverse(id), body: {'event_id': eventId});
    return postOutcome(res, (m) => m['entry_id']?.toString());
  }

  Future<RawPage> fetchVendorAdvances({String? vendor, String? status, int page = 1}) =>
      _list(ApiEndpoints.accVendorAdvances, {'vendor': vendor, 'status': status}, page);

  // ── Purchases (post immediately; no draft, no preview — §12.9) ──

  Future<PostOutcome<AccDocument>> recordVendorBill(Map<String, Object?> body) async {
    final res = await _api.post(ApiEndpoints.accVendorBills, body: compact(body));
    return postOutcome(res, mapDocument);
  }

  /// A bill and its payment in one call → `{bill, payment_id, payment_entry_id}`.
  Future<PostOutcome<AccDocument>> recordExpense(Map<String, Object?> body) async {
    final res = await _api.post(ApiEndpoints.accExpenses, body: compact(body));
    return postOutcome(res, (m) => m['bill'] is Map ? mapDocument(Map<String, dynamic>.from(m['bill'] as Map)) : null);
  }
}
