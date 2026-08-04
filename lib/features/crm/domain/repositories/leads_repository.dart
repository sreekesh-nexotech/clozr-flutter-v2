import '../entities/lead.dart';

/// Abstract contract for lead data. The presentation layer depends only on
/// this; whether leads come from a mock source or a REST API is an
/// infrastructure detail.
abstract class LeadsRepository {
  Future<List<Lead>> getLeads();

  /// Creates a lead from API-shaped form fields (`lead_name`,
  /// `organization_name`, `email`, `phone`, `purpose`). Returns the created
  /// lead, or null when the backend response shape is unexpected.
  Future<Lead?> createLead(Map<String, dynamic> fields);
}
