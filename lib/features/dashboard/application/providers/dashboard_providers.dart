import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
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

/// Holds the dashboard bundle. Seeded with the mock bundle so the panels paint
/// instantly in both modes; [load] swaps in mapped API data when it lands and
/// keeps the last good bundle on any failure.
class DashboardDataNotifier extends StateNotifier<DashboardData> {
  DashboardDataNotifier(this._repository)
      : super(const DashboardMockDataSource().load());

  final DashboardRepository _repository;
  int _requestSeq = 0;

  Future<void> load({String period = 'month', String? teamId}) async {
    final seq = ++_requestSeq;
    try {
      final data = await _repository.getDashboard(period: period, teamId: teamId);
      // A newer request (period/team changed mid-flight) wins.
      if (mounted && seq == _requestSeq) state = data;
    } on Object {
      // Silent: a failed refresh keeps the last data on screen.
    }
  }
}

/// Internal loader; screens keep watching [dashboardDataProvider] below.
final dashboardDataNotifierProvider =
    StateNotifierProvider<DashboardDataNotifier, DashboardData>((ref) {
  final notifier = DashboardDataNotifier(ref.watch(dashboardRepositoryProvider));
  if (ApiConfig.apiEnabled) {
    void reload() {
      notifier.load(
        period: dashApiPeriod(ref.read(dashPeriodProvider)),
        teamId: ref.read(dashTeamProvider),
      );
    }

    ref.listen<String>(dashPeriodProvider, (_, __) => reload());
    ref.listen<String>(dashTeamProvider, (_, __) => reload());
    reload();
  }
  return notifier;
});

/// The full four-panel dashboard bundle (same sync surface as before).
final dashboardDataProvider = Provider<DashboardData>(
  (ref) => ref.watch(dashboardDataNotifierProvider),
);

// ── Scope selectors (functional selection state) ──

/// Active period label shown in the period chip (prototype default "This month").
final dashPeriodProvider = StateProvider<String>((ref) => 'This month');

/// Selected team id for the team chip ('all' → All teams).
final dashTeamProvider = StateProvider<String>((ref) => 'all');

// ── Per-panel toggle state ──

/// CRM · Lead Sources segment (0 = Leads, 1 = ₹ Value).
final dashSourceModeProvider = StateProvider<int>((ref) => 0);

/// CRM · Stuck Items active chip ('stale' | 'quotes' | 'payments' | 'wonnc').
final dashStuckChipProvider = StateProvider<String>((ref) => 'stale');

/// Operations · Overdue Tasks segment (0 = ₹ Value, 1 = Days).
final dashOpsValueModeProvider = StateProvider<int>((ref) => 0);

/// Operations · Active Projects segment ('all' | 'risk' | 'overdue').
final dashActiveProjTabProvider = StateProvider<String>((ref) => 'all');

/// Resolve the selected team's display name for the chip label.
String dashTeamLabel(DashboardData data, String id) {
  for (final t in data.teamOptions) {
    if (t.id == id) return t.id == 'all' ? 'All teams' : t.name;
  }
  return 'All teams';
}
