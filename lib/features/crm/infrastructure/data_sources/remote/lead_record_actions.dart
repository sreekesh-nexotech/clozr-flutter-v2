import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';

/// Lead detail ⋯ › Archive / Delete (UI/UX audit #14 — the detail page had
/// neither, and mobile has no bulk actions, so a lead could not be removed).
///
/// Archive goes through the webapp's `bulk-archive` (one id); `is_archive` is
/// required by the API. Delete is the record's own `DELETE`.
class LeadRecordActions {
  const LeadRecordActions(this._api);
  final ApiService _api;

  Future<void> archive(String leadId, {bool archive = true}) => _api.post(
        '${ApiEndpoints.leads}bulk-archive/',
        body: {
          'lead_ids': [leadId],
          'is_archive': archive,
        },
      );

  Future<void> delete(String leadId) => _api.delete(ApiEndpoints.lead(leadId));
}
