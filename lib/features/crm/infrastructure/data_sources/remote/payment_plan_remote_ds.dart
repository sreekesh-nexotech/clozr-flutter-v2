import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../application/payment_plan/payment_plan_detail.dart';

/// The payment-plan detail screen's own calls — the raw plan / record detail
/// reads and the plan actions the webapp's `payments.api.ts` makes:
///
/// * `GET  /quotations/payments/{payment_id}/`
/// * `POST /quotations/payments/{payment_id}/schedule/` — re-split (round 3)
/// * `POST /quotations/payments/{payment_id}/stop-recurring/` — D-3(b)
/// * `GET  /quotations/payment-records/{record_id}/`
/// * `POST /quotations/payment-records/` — a milestone (UAT R2 QT-11)
/// * `DELETE /quotations/payment-records/{record_id}/`
/// * `GET  /quotations/quotations/{quotation_id}/` — only for the quote's
///   `lead`, which a lead-only plan does not carry itself.
class PaymentPlanRemoteDataSource {
  const PaymentPlanRemoteDataSource(this._api);

  final ApiService _api;

  static Map<String, dynamic> _obj(Object? body) {
    if (body is Map) {
      final m = Map<String, dynamic>.from(body);
      // Some views wrap the record in `{data: …}`.
      final inner = m['data'];
      if (inner is Map && !m.containsKey('payment_id') && !m.containsKey('record_id')) {
        return Map<String, dynamic>.from(inner);
      }
      return m;
    }
    return const {};
  }

  Future<PlanDetail> getPlan(String planId) async =>
      PlanDetail.fromJson(_obj(await _api.get(ApiEndpoints.payment(planId))));

  Future<PlanRecord> getRecord(String recordId) async =>
      PlanRecord.fromJson(_obj(await _api.get(ApiEndpoints.paymentRecord(recordId))));

  /// The quote's `lead` UUID ('' when none or unreadable). Best-effort.
  Future<String> getQuoteLeadId(String quotationId) async {
    final body = _obj(await _api.get(ApiEndpoints.quotation(quotationId), quiet: true));
    final lead = body['lead'];
    if (lead is Map) return '${lead['lead_id'] ?? lead['id'] ?? ''}';
    return lead is String ? lead : '';
  }

  /// Re-split the plan. Answers the updated plan.
  Future<PlanDetail> schedulePlan(String planId, Map<String, dynamic> body) async =>
      PlanDetail.fromJson(_obj(await _api.post('${ApiEndpoints.payment(planId)}schedule/', body: body)));

  /// Stop recurring billing from [stopFrom] (`YYYY-MM-DD`).
  Future<void> stopRecurring(String planId, String stopFrom) =>
      _api.post('${ApiEndpoints.payment(planId)}stop-recurring/', body: {'stop_from': stopFrom});

  Future<void> addMilestone(Map<String, dynamic> body) => _api.post(ApiEndpoints.paymentRecords, body: body);

  Future<void> deleteRecord(String recordId) => _api.delete(ApiEndpoints.paymentRecord(recordId));
}
