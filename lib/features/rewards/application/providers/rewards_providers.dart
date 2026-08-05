import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
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

/// Immutable My Rewards UI state: the bundle plus a load phase.
class RewardsState {
  const RewardsState({required this.data, this.loading = false, this.error});

  final RewardsData data;
  final bool loading;
  final AppError? error;

  RewardsState copyWith({
    RewardsData? data,
    bool? loading,
    AppError? error,
    bool clearError = false,
  }) =>
      RewardsState(
        data: data ?? this.data,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Load-then-notify holder.
///
/// - MOCK mode: seeds the mock bundle synchronously and never loads (byte
///   identical to the prototype — the screen renders the seed on the first
///   frame).
/// - API mode: seeds an EMPTY bundle + loading (never mock), fetches+maps the
///   milestone endpoints, and stores an error phase on failure. [reload]
///   drives the retry.
class RewardsNotifier extends StateNotifier<RewardsState> {
  RewardsNotifier(this._repo)
      : super(ApiConfig.apiEnabled
            ? RewardsState(data: RewardsData.empty(), loading: true)
            : RewardsState(data: _mockBundle)) {
    if (ApiConfig.apiEnabled) _load();
  }

  final RewardsRepository _repo;

  static final RewardsData _mockBundle = const RewardsMockDataSource().fetch();

  Future<void> _load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final value = await _repo.getRewards();
      if (mounted) state = RewardsState(data: value);
    } on AppError catch (e) {
      if (mounted) state = state.copyWith(loading: false, error: e);
    } on Object catch (e) {
      if (mounted) {
        state = state.copyWith(
          loading: false,
          error: AppError(type: AppErrorType.unknown, message: 'Something went wrong. Please try again.', cause: e),
        );
      }
    }
  }

  /// Retry the milestone fetch (used by the error-state Retry CTA).
  void reload() => _load();
}

/// Controller state (bundle + loading/error) — the screen reads this for the
/// load-phase branch and `.notifier.reload` for retry.
final rewardsControllerProvider =
    StateNotifierProvider<RewardsNotifier, RewardsState>((ref) {
  return RewardsNotifier(ref.watch(rewardsRepositoryProvider));
});

/// The full My Rewards payload (profile + goals + closer track). Same
/// name/exposed type as before the API wiring.
final rewardsProvider = Provider<RewardsData>(
  (ref) => ref.watch(rewardsControllerProvider).data,
);

/// Ids of goal cards whose "past periods" section is expanded.
final rewardsExpandedProvider = StateProvider<Set<String>>((ref) => <String>{});
