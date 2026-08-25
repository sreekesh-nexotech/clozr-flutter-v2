import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
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
  return OpsDashboardRemoteDataSource(ref.watch(apiServiceProvider)).fetchKpis();
});

/// The completed-tasks grid, split by priority and by early/late, scoped to the
/// signed-in user.
///
/// Empty in mock mode and whenever the call fails, which the card reads as
/// "derive it from the task list instead".
final opsCompletedGridProvider = FutureProvider<List<OpsCompletedRow>>((ref) async {
  if (!ApiConfig.apiEnabled) return const [];
  return OpsDashboardRemoteDataSource(ref.watch(apiServiceProvider))
      .fetchCompletedGrid();
});
