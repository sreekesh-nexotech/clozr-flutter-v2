import '../../domain/entities/reward.dart';
import '../../domain/repositories/rewards_repository.dart';
import '../data_sources/local/rewards_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one when the
/// API lands — the interface and every caller stay the same.
class RewardsRepositoryImpl implements RewardsRepository {
  const RewardsRepositoryImpl(this._local);

  final RewardsMockDataSource _local;

  @override
  RewardsData getRewards() => _local.fetch();
}
