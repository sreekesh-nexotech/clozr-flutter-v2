import '../entities/lead.dart';

/// Abstract contract for lead data. The presentation layer depends only on
/// this; whether leads come from a mock source or a REST API is an
/// infrastructure detail.
abstract class LeadsRepository {
  Future<List<Lead>> getLeads();
}
