import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/reward.dart';
import '../../domain/repositories/rewards_repository.dart';
import '../../infrastructure/data_sources/local/rewards_mock_ds.dart';
import '../../infrastructure/data_sources/remote/rewards_remote_ds.dart';
import '../../infrastructure/repositories/rewards_api_repository.dart';
import '../../infrastructure/repositories/rewards_repository_impl.dart';

/// DI seam: mock-backed by default; API-backed when a base URL is configured.
final rewardsRepositoryProvider = Provider<RewardsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const RewardsRepositoryImpl(RewardsMockDataSource());
  }
  return RewardsApiRepository(
    RewardsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Load-then-notify holder. Starts from the mock bundle in BOTH modes (it is
/// the only sane default shape — the screen renders synchronously) and, in
/// API mode, replaces itself once the milestone endpoints are fetched+mapped.
class RewardsNotifier extends StateNotifier<RewardsData> {
  RewardsNotifier(super.seed, RewardsRepository repo, {bool refresh = false}) {
    if (refresh) _load(repo);
  }

  Future<void> _load(RewardsRepository repo) async {
    try {
      final value = await repo.getRewards();
      if (mounted) state = value;
    } on Object {
      // Keep the seed; the next app launch retries.
    }
  }
}

final _rewardsNotifierProvider =
    StateNotifierProvider<RewardsNotifier, RewardsData>((ref) {
  final repo = ref.watch(rewardsRepositoryProvider);
  return RewardsNotifier(
    const RewardsMockDataSource().fetch(),
    repo,
    refresh: ApiConfig.apiEnabled,
  );
});

/// The full My Rewards payload (profile + goals + closer track). Same
/// name/exposed type as before the API wiring.
final rewardsProvider = Provider<RewardsData>(
  (ref) => ref.watch(_rewardsNotifierProvider),
);

/// Ids of goal cards whose "past periods" section is expanded.
final rewardsExpandedProvider = StateProvider<Set<String>>((ref) => <String>{});
