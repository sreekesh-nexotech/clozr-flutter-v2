import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../domain/entities/exotel_status.dart';

/// Exotel click-to-call (`/crm/exotel/`).
///
/// Exotel does not dial from the device: it rings the **agent's own phone**
/// first and then bridges to the lead. So this places a request, it does not
/// hand anything to a dialler.
class ExotelRemoteDataSource {
  const ExotelRemoteDataSource(this._api);

  final ApiService _api;

  /// `GET /crm/exotel/status/`.
  ///
  /// Best-effort: any failure — including the 403 a non-admin gets, since the
  /// endpoint is settings-gated — resolves to [ExotelStatus.unknown] rather
  /// than "off". The caller treats unknown as "try it and see".
  Future<ExotelStatus> fetchStatus() async {
    try {
      final body = await _api.get(ApiEndpoints.exotelStatus);
      if (body is! Map) return const ExotelStatus.unknown();
      return ExotelStatus(
        enabled: body['enabled'] == true,
        configured: body['configured'] == true,
      );
    } on Object {
      return const ExotelStatus.unknown();
    }
  }

  /// `POST /crm/exotel/call/` — starts a click-to-call against a lead, or any
  /// other number when [leadId] is null (e.g. a WhatsApp contact not yet
  /// linked to a lead).
  ///
  /// `related_to` / `related_to_id` are both-or-neither by contract, and pin
  /// the resulting log to *this* lead even when the number also matches another
  /// record. Omitted entirely when [leadId] is null — the backend then falls
  /// back to reverse-resolving the dialled number (Contact → Lead → Customer).
  /// `from_number` and `caller_id` are deliberately omitted: the server fills
  /// them from the caller's telephony-agent row, which is the only place those
  /// numbers exist.
  ///
  /// **The backend creates the call log itself**, at dial time, and returns its
  /// id — so a caller must not also post to `/crm/call-logs/`, or the call
  /// lands in the history twice.
  ///
  /// Throws on refusal (integration off, caller not an agent, upstream error);
  /// no call is placed in any of those cases.
  Future<String?> placeCall({
    String? leadId,
    required String toNumber,
  }) async {
    final body = await _api.post(ApiEndpoints.exotelCall, body: {
      'to_number': toNumber,
      if (leadId != null) 'related_to': 'lead',
      if (leadId != null) 'related_to_id': leadId,
    });
    return body is Map ? body['call_log_id']?.toString() : null;
  }
}
