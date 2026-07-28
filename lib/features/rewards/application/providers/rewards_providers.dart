import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/reward.dart';
import '../../domain/repositories/rewards_repository.dart';
import '../../infrastructure/data_sources/local/rewards_mock_ds.dart';
import '../../infrastructure/repositories/rewards_repository_impl.dart';

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final rewardsRepositoryProvider = Provider<RewardsRepository>(
  (ref) => const RewardsRepositoryImpl(RewardsMockDataSource()),
);

/// The full My Rewards payload (profile + goals + closer track).
final rewardsProvider = Provider<RewardsData>(
  (ref) => ref.watch(rewardsRepositoryProvider).getRewards(),
);

/// Ids of goal cards whose "past periods" section is expanded.
final rewardsExpandedProvider = StateProvider<Set<String>>((ref) => <String>{});
