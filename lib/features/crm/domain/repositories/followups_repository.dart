import '../entities/followup.dart';

/// Abstract contract for follow-up data.
abstract class FollowupsRepository {
  Future<List<Followup>> getFollowups();
}
