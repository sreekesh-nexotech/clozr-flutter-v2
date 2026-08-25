import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../domain/entities/ops_kpis.dart';

/// The PMO dashboard figures the Operations home reads
/// (`admin_operations_dashboard.md`).
///
/// Separate from the manager dashboard's bundle fetch: this screen wants one
/// endpoint, scoped to the signed-in user, not the twenty-odd widget calls the
/// Overview tab makes.
class OpsDashboardRemoteDataSource {
  const OpsDashboardRemoteDataSource(this._api);

  final ApiService _api;

  /// `GET /crm/dashboard-pmo/kpis/?scope=own&period=…` (§1).
  ///
  /// `scope=own` is the caller's own data and the endpoint's default; only
  /// `scope=admin` needs an org-admin role. The route group still sits behind
  /// `view_dashboard`, so a user without it gets a 403 — hence best-effort:
  /// **any** failure answers null, and the screen falls back to the counts it
  /// derives from the task and project lists. A dashboard that renders is worth
  /// more than a trend chip.
  Future<OpsKpis?> fetchKpis({
    String scope = 'own',
    String period = 'month',
  }) async {
    try {
      final body = await _api.get(
        ApiEndpoints.dashboardPmoKpis,
        query: {'scope': scope, 'period': period},
      );
      return OpsKpis.fromJson(body);
    } on Object {
      return null;
    }
  }

  /// `GET /crm/dashboard-pmo/tasks-completed-grid/?scope=own&period=…`.
  ///
  /// Empty on any failure, which the grid reads as "count it yourself from the
  /// task list" — the same best-effort contract as [fetchKpis].
  Future<List<OpsCompletedRow>> fetchCompletedGrid({
    String scope = 'own',
    String period = 'month',
  }) async {
    try {
      final body = await _api.get(
        ApiEndpoints.dashboardPmoCompletedGrid,
        query: {'scope': scope, 'period': period},
      );
      return OpsCompletedRow.listFromJson(body);
    } on Object {
      return const [];
    }
  }
}
