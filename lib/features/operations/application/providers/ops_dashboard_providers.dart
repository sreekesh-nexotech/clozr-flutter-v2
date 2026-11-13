import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../dashboard/application/providers/dashboard_providers.dart';
import '../../../helpdesk/application/providers/help_dashboard_providers.dart'
    show serverOwnScopeIsPersonal;
import '../../domain/entities/ops_kpis.dart';
import '../../infrastructure/data_sources/remote/ops_dashboard_remote_ds.dart';

/// The PMO KPI figures behind the Operations home cards, scoped to the
/// signed-in user (`admin_operations_dashboard.md` §1).
///
/// Null in mock mode, while it loads, and whenever the call fails — including
/// the 403 a user without `view_dashboard` gets. The screen treats null as "no
/// trend to show, and no server figure for avg cycle" and keeps rendering the
/// counts it derives from the task and project lists, so the dashboard never
/// depends on this call succeeding.
final opsKpisProvider = FutureProvider<OpsKpis?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  // `scope=own` is org-wide for staff accounts (see serverOwnScopeIsPersonal).
  if (!await serverOwnScopeIsPersonal(ref)) return null;
  final p = ref.watch(opsPeriodQueryProvider);
  return OpsDashboardRemoteDataSource(ref.watch(apiServiceProvider))
      .fetchKpis(period: p.period, from: p.from, to: p.to);
});

/// The completed-tasks grid, split by priority and by early/late, scoped to the
/// signed-in user.
///
/// Empty in mock mode and whenever the call fails, which the card reads as
/// "derive it from the task list instead".
final opsCompletedGridProvider =
    FutureProvider<List<OpsCompletedRow>>((ref) async {
  if (!ApiConfig.apiEnabled) return const [];
  if (!await serverOwnScopeIsPersonal(ref)) return const [];
  final p = ref.watch(opsPeriodQueryProvider);
  return OpsDashboardRemoteDataSource(ref.watch(apiServiceProvider))
      .fetchCompletedGrid(period: p.period, from: p.from, to: p.to);
});

/// The Period the Operations home asks the server for — the same selection the
/// Dashboard tabs use (`dashPeriodProvider` + `dashCustomRangeProvider`), as the
/// `period` / `from` / `to` query values.
final opsPeriodQueryProvider =
    Provider<({String period, String? from, String? to})>((ref) {
  final range = ref.watch(dashCustomRangeProvider);
  if (range != null) {
    String d(DateTime t) =>
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return (period: 'custom', from: d(range.start), to: d(range.end));
  }
  return (
    period: dashApiPeriod(ref.watch(dashPeriodProvider)),
    from: null,
    to: null,
  );
});
