import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/help_dashboard.dart';
import '../../domain/entities/help_kpis.dart';
import '../../infrastructure/data_sources/remote/help_dashboard_remote_ds.dart';

/// The Helpdesk KPI figures behind the home cards, scoped to the signed-in
/// user.
///
/// Null in mock mode, while it loads, and whenever the call fails (a 403 for a
/// user without the dashboard permission included). The screen treats null as
/// "no trend chip, and no server median", keeping the counts it derives from
/// the ticket list — so the grid never depends on this call succeeding.
final helpKpisProvider = FutureProvider<HelpKpis?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  return HelpDashboardRemoteDataSource(ref.watch(apiServiceProvider)).fetchKpis();
});

/// §3 — the SLA Status and Priority Mix donuts.
///
/// Null in mock mode and on failure, which the card reads as "count the loaded
/// tickets instead", the same contract as [helpKpisProvider].
final helpSlaMixProvider = FutureProvider<SlaPriorityMix?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  return HelpDashboardRemoteDataSource(ref.watch(apiServiceProvider))
      .fetchSlaPriorityMix();
});

/// §9 — the Tickets Resolved grid, priority × before/after due.
final helpCompletedGridProvider =
    FutureProvider<List<CompletedGridRow>?>((ref) async {
  if (!ApiConfig.apiEnabled) return null;
  return HelpDashboardRemoteDataSource(ref.watch(apiServiceProvider))
      .fetchCompletedGrid();
});
