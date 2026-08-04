import '../../domain/entities/reward.dart';
import '../../domain/repositories/rewards_repository.dart';
import '../data_sources/local/rewards_mock_ds.dart';

/// Mock-backed implementation. The API twin is `RewardsApiRepository`; the
/// interface and every caller stay the same.
class RewardsRepositoryImpl implements RewardsRepository {
  const RewardsRepositoryImpl(this._local);

  final RewardsMockDataSource _local;

  @override
  Future<RewardsData> getRewards() => Future.value(_local.fetch());
}
