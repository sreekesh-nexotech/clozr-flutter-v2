import '../entities/reward.dart';

/// Abstract contract for rewards data. The presentation layer depends only on
/// this; mock vs REST is an infrastructure detail. The read is async (mock
/// mode resolves immediately); the screen renders synchronously from a
/// load-then-notify provider seeded with the mock bundle.
abstract class RewardsRepository {
  Future<RewardsData> getRewards();
}
