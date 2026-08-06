import '../entities/lead.dart';

/// Abstract contract for lead data. The presentation layer depends only on
/// this; whether leads come from a mock source or a REST API is an
/// infrastructure detail.
abstract class LeadsRepository {
  /// [mineOnly] scopes the list to leads the signed-in user owns **or** is
  /// assigned to — the "My leads" view. API mode sends this to the server as
  /// `?is_teams=true`; mock mode applies the same rule locally.
  Future<List<Lead>> getLeads({bool mineOnly = false});

  /// Creates a lead from API-shaped form fields (`lead_name`,
  /// `organization_name`, `email`, `phone`, `purpose`). Returns the created
  /// lead, or null when the backend response shape is unexpected.
  Future<Lead?> createLead(Map<String, dynamic> fields);
}
