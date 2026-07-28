import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/dashboard_models.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../infrastructure/data_sources/local/dashboard_mock_ds.dart';
import '../../infrastructure/repositories/dashboard_repository_impl.dart';

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => const DashboardRepositoryImpl(DashboardMockDataSource()),
);

/// The full four-panel dashboard bundle.
final dashboardDataProvider = Provider<DashboardData>(
  (ref) => ref.watch(dashboardRepositoryProvider).getDashboard(),
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
