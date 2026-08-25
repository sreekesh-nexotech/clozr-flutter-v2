import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/dashboard_models.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../infrastructure/data_sources/local/dashboard_mock_ds.dart';
import '../../infrastructure/data_sources/remote/dashboard_remote_ds.dart';
import '../../infrastructure/repositories/dashboard_api_repository.dart';
import '../../infrastructure/repositories/dashboard_repository_impl.dart';

/// DI seam: mock-backed without a base URL, API-backed otherwise.
final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const DashboardRepositoryImpl(DashboardMockDataSource());
  }
  return DashboardApiRepository(
    DashboardRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Maps the period chip's display label onto the API `period` value. Custom
/// range labels ("5 Jun – 12 Jun") carry no machine-readable dates on the
/// chip, so they conservatively fall back to the default month window.
String dashApiPeriod(String label) {
  switch (label) {
    case 'This month':
      return 'month';
    case 'Last month':
      return 'last_month';
    case 'This quarter':
      return 'this_quarter';
    case 'Year to date':
      return 'ytd';
    case 'Last 30 days':
      return 'last_30_days';
    case 'Last 90 days':
      return 'last_90_days';
  }
  return 'month';
}

/// The dashboard's load phase: the current bundle plus loading/error flags so
/// the screen can branch skeleton → error → panels. [settled] flips true once a
/// first load has resolved, so a background refresh (period/team change) never
/// flashes the skeleton over already-real data.
class DashboardPhase {
  const DashboardPhase({
    required this.data,
    this.loading = false,
    this.error,
    this.settled = false,
  });

  final DashboardData data;
  final bool loading;
  final AppError? error;
  final bool settled;

  DashboardPhase copyWith({
    DashboardData? data,
    bool? loading,
    AppError? error,
    bool clearError = false,
    bool? settled,
  }) =>
      DashboardPhase(
        data: data ?? this.data,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        settled: settled ?? this.settled,
      );
}

/// Holds the dashboard bundle and its load phase.
///
/// - **Mock mode:** seeded synchronously with the mock bundle, already settled —
///   the panels paint the seed exactly as before and [load] is a no-op, so mock
///   behaviour stays byte-identical.
/// - **API mode:** seeded with [DashboardData.empty] in a loading state; [load]
///   maps real API data on success or stores an [AppError] on total failure. It
///   NEVER falls back to mock — a failure surfaces as an error, not fake data.
class DashboardDataNotifier extends StateNotifier<DashboardPhase> {
  DashboardDataNotifier.mock()
      : _repository = null,
        super(DashboardPhase(data: const DashboardMockDataSource().load(), settled: true));

  DashboardDataNotifier.api(DashboardRepository repository)
      : _repository = repository,
        super(DashboardPhase(data: DashboardData.empty(), loading: true));

  final DashboardRepository? _repository;
  int _requestSeq = 0;
  String _period = 'month';
  String? _teamId;
  String? _userId;

  Future<void> load({String period = 'month', String? teamId, String? userId}) async {
    final repo = _repository;
    if (repo == null) return; // mock mode: the seed never refreshes.
    _period = period;
    _teamId = teamId;
    _userId = userId;
    final seq = ++_requestSeq;
    if (mounted) state = state.copyWith(loading: true, clearError: true);
    try {
      final data =
          await repo.getDashboard(period: period, teamId: teamId, userId: userId);
      // A newer request (period/team changed mid-flight) wins.
      if (mounted && seq == _requestSeq) {
        state = DashboardPhase(data: data, loading: false, settled: true);
      }
    } on AppError catch (e) {
      if (mounted && seq == _requestSeq) {
        state = state.copyWith(loading: false, error: e, settled: true);
      }
    } on Object catch (e) {
      if (mounted && seq == _requestSeq) {
        state = state.copyWith(
          loading: false,
          settled: true,
          error: AppError(
            type: AppErrorType.unknown,
            message: 'Something went wrong. Please try again.',
            cause: e,
          ),
        );
      }
    }
  }

  /// Re-runs the last request — wired to the error state's Retry.
  Future<void> reload() =>
      load(period: _period, teamId: _teamId, userId: _userId);
}

/// Internal loader; the screen reads phase from here, panels read the bundle
/// from [dashboardDataProvider] below.
final dashboardDataNotifierProvider =
    StateNotifierProvider<DashboardDataNotifier, DashboardPhase>((ref) {
  if (!ApiConfig.apiEnabled) {
    return DashboardDataNotifier.mock();
  }
  final notifier = DashboardDataNotifier.api(ref.watch(dashboardRepositoryProvider));
  void reload() {
    notifier.load(
      period: dashApiPeriod(ref.read(dashPeriodProvider)),
      teamId: ref.read(dashTeamProvider),
      userId: ref.read(dashMemberProvider),
    );
  }

  ref.listen<String>(dashPeriodProvider, (_, __) => reload());
  ref.listen<String>(dashTeamProvider, (_, __) => reload());
  ref.listen<String>(dashMemberProvider, (_, __) => reload());
  reload();
  return notifier;
});

/// The full four-panel dashboard bundle (same sync surface the panels watch).
final dashboardDataProvider = Provider<DashboardData>(
  (ref) => ref.watch(dashboardDataNotifierProvider).data,
);

// ── Scope selectors (functional selection state) ──

/// Active period label shown in the period chip (prototype default "This month").
final dashPeriodProvider = StateProvider<String>((ref) => 'This month');

/// Selected team id for the team chip ('all' → All teams).
final dashTeamProvider = StateProvider<String>((ref) => 'all');

/// Selected member id for the member chip (empty → All members).
final dashMemberProvider = StateProvider<String>((ref) => '');

/// The Member dropdown's options for one panel, from
/// `/dashboard-new/users/?module=…&team_id=…`.
///
/// Keyed by both because the API requires `module` and scopes the list to the
/// selected team — a member list is not shared across panels or teams.
final dashMemberOptionsProvider = FutureProvider.autoDispose
    .family<List<DashTeamOption>, ({String module, String teamId})>((ref, key) {
  if (!ApiConfig.apiEnabled) return Future.value(const <DashTeamOption>[]);
  return DashboardRemoteDataSource(ref.watch(apiServiceProvider))
      .fetchMembers(module: key.module, teamId: key.teamId);
});

// ── Per-panel toggle state ──

/// CRM · Lead Sources segment (0 = Leads, 1 = ₹ Value).
final dashSourceModeProvider = StateProvider<int>((ref) => 0);

/// CRM · Stuck Items active chip ('stale' | 'quotes' | 'payments' | 'wonnc').
final dashStuckChipProvider = StateProvider<String>((ref) => 'stale');

/// Operations · Overdue Tasks segment (0 = ₹ Value, 1 = Days).
final dashOpsValueModeProvider = StateProvider<int>((ref) => 0);

/// Operations · Active Projects segment ('all' | 'risk' | 'overdue').
final dashActiveProjTabProvider = StateProvider<String>((ref) => 'all');

/// Resolve the selected member's display name for the chip label. Falls back to
/// "All members" — including for a member the current list no longer contains,
/// which is what a stale selection looks like after a team change.
String dashMemberLabel(List<DashTeamOption> options, String id) {
  if (id.isEmpty) return 'All members';
  for (final m in options) {
    if (m.id == id) return m.name;
  }
  return 'All members';
}

/// Resolve the selected team's display name for the chip label.
String dashTeamLabel(DashboardData data, String id) {
  for (final t in data.teamOptions) {
    if (t.id == id) return t.id == 'all' ? 'All teams' : t.name;
  }
  return 'All teams';
}
