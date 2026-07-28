import '../entities/reward.dart';

/// Abstract contract for rewards data. The presentation layer depends only on
/// this; mock vs REST is an infrastructure detail.
abstract class RewardsRepository {
  RewardsData getRewards();
}
