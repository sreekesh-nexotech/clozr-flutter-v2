import '../entities/followup.dart';

/// Abstract contract for follow-up data.
abstract class FollowupsRepository {
  Future<List<Followup>> getFollowups();

  /// Creates a follow-up from the Add-follow-up sheet's fields
  /// (`title` / `task_type` / `due_date` / `description`). Returns the created
  /// follow-up, or null when the response shape was unexpected.
  Future<Followup?> createFollowup(Map<String, dynamic> fields);

  /// Marks a follow-up done (or reopens it when [done] is false).
  Future<void> setFollowupDone(String id, bool done);
}
