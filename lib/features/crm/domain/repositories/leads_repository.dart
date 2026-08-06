import '../entities/lead.dart';

/// Abstract contract for lead data. The presentation layer depends only on
/// this; whether leads come from a mock source or a REST API is an
/// infrastructure detail.
abstract class LeadsRepository {
  /// [mineOnly] scopes the list to leads the signed-in user owns **or** is
  /// assigned to — the "My leads" view. API mode sends this to the server as
  /// `?is_teams=true`; mock mode applies the same rule locally.
  ///
  /// [filters] are `LeadFilter` query params (`status__not`, `lead_source__in`,
  /// …) evaluated **by the server**, so a negation is resolved against the
  /// whole org rather than the rows that happen to be loaded. Always empty in
  /// mock mode, which has no query engine — there the caller matches locally.
  Future<List<Lead>> getLeads({
    bool mineOnly = false,
    Map<String, dynamic> filters = const {},
  });

  /// One lead by id, from the **record** endpoint.
  ///
  /// Not the same data as finding the lead in [getLeads]: the two endpoints are
  /// trimmed to different field configs, so the record carries fields the list
  /// omits entirely (`lead_owner`, `email`, `mobile_no`, `whatsapp_no`,
  /// `territory`). The detail screen needs this one.
  ///
  /// Returns null when no such lead is visible to the caller.
  Future<Lead?> getLead(String id);

  /// Moves a lead to another pipeline stage. [statusId] is a `lead_status_id`
  /// from the org's `/crm/lead-statuses/` catalog.
  ///
  /// Returns the updated lead, or null when the backend response shape is
  /// unexpected. Throws on a rejected write — the caller surfaces it, because
  /// silently leaving the old status on screen would be a lie.
  Future<Lead?> updateLeadStatus(String leadId, String statusId);

  /// Creates a lead from API-shaped form fields (`lead_name`,
  /// `organization_name`, `email`, `phone`, `purpose`). Returns the created
  /// lead, or null when the backend response shape is unexpected.
  Future<Lead?> createLead(Map<String, dynamic> fields);
}
