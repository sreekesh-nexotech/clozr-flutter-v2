import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../application/record_payment/record_payment_logic.dart';
import '../../../application/record_payment/record_payment_plan.dart';

/// The Record payment sheet's own reads and writes — webapp
/// `payments.api.ts` (plans, records) and `leads.api.ts` (the quote's lead,
/// statuses, Won move). Bodies are built by `record_payment_logic.dart`.
class RecordPaymentRemoteDataSource {
  const RecordPaymentRemoteDataSource(this._api);

  final ApiService _api;

  /// Plan picker: `GET /quotations/payments/?page=1&page_size=50&search=q`
  /// (webapp `useInvoicesQuery({page: 1, pageSize: 50, search})`).
  Future<List<PlanOption>> searchPlans(String query) async {
    final body = await _api.get(ApiEndpoints.payments, query: {
      'page': 1,
      'page_size': 50,
      if (query.trim().isNotEmpty) 'search': query.trim(),
    });
    return [
      for (final r in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results)
        if ('${r['payment_id'] ?? ''}'.isNotEmpty) PlanOption.fromJson(r),
    ];
  }

  /// One plan with its records: `GET /quotations/payments/{id}/`.
  Future<RecordPaymentPlan?> getPlan(String id) async {
    final body = await _api.get(ApiEndpoints.payment(id));
    return body is Map ? RecordPaymentPlan.fromJson(Map<String, dynamic>.from(body)) : null;
  }

  /// Settle: `PATCH /quotations/payment-records/{id}/` with [buildSettleBody].
  /// Returns the saved record.
  Future<Map<String, dynamic>> settleRecord(String recordId, Map<String, dynamic> body) async {
    final res = await _api.patch(ApiEndpoints.paymentRecord(recordId), body: body);
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Ad-hoc: `POST /quotations/payment-records/` with [buildAdhocBody].
  Future<Map<String, dynamic>> addRecord(Map<String, dynamic> body) async {
    final res = await _api.post(ApiEndpoints.paymentRecords, body: body);
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// The lead behind a quote (`GET /quotations/quotations/{id}/` → `lead`).
  Future<String?> quotationLeadId(String quotationUuid) async {
    final body = await _api.get(ApiEndpoints.quotation(quotationUuid));
    final lead = body is Map ? body['lead'] : null;
    if (lead is Map) {
      final id = '${lead['lead_id'] ?? lead['id'] ?? ''}';
      return id.isEmpty ? null : id;
    }
    return lead is String && lead.isNotEmpty ? lead : null;
  }

  /// Webapp `getQuoteLeadConversion`: the lead record plus the org's statuses.
  Future<QuoteLeadState> quoteLeadState(String leadId) async {
    final results = await Future.wait([
      _api.get(ApiEndpoints.lead(leadId)),
      _api.get(ApiEndpoints.leadStatuses, query: {'page_size': 100}),
    ]);
    final lead = results[0] is Map ? Map<String, dynamic>.from(results[0] as Map) : <String, dynamic>{};
    final statuses = Paginated.fromAny<Map<String, dynamic>>(results[1], (m) => m).results;
    return quoteLeadStateFrom(leadId, lead, statuses);
  }

  /// The normal lead status move (`PATCH /crm/leads/{id}/ {status_id}`).
  Future<void> moveLeadToStatus(String leadId, String statusId) =>
      _api.patch(ApiEndpoints.lead(leadId), body: {'status_id': statusId});

  /// The raw lead record, re-read after a Won move (auto-convert / approval).
  Future<Map<String, dynamic>> leadRow(String leadId) async {
    final body = await _api.get(ApiEndpoints.lead(leadId));
    return body is Map ? Map<String, dynamic>.from(body) : const {};
  }
}
