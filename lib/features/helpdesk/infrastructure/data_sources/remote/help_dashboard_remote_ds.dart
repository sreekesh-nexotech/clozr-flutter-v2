import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../domain/entities/help_dashboard.dart';
import '../../../domain/entities/help_kpis.dart';

/// The Helpdesk dashboard figures the Helpdesk home reads.
///
/// Separate from the manager dashboard's bundle fetch: this screen wants one
/// endpoint, scoped to the signed-in user, not the twenty-odd widget calls the
/// Overview tab makes.
class HelpDashboardRemoteDataSource {
  const HelpDashboardRemoteDataSource(this._api);

  final ApiService _api;

  /// The shared query: a custom range also carries its `from` / `to` dates.
  static Map<String, String> _query(
          String scope, String period, String? from, String? to) =>
      {
        'scope': scope,
        'period': period,
        if (period == 'custom' && from != null && to != null) ...{
          'from': from,
          'to': to,
        },
      };

  /// `GET /crm/dashboard-issue/kpis/?scope=own&period=…`.
  ///
  /// Best-effort: **any** failure answers null — including the 403 a user
  /// without the dashboard permission gets — and the screen falls back to the
  /// counts it derives from the ticket list. A dashboard that renders is worth
  /// more than a trend chip.
  Future<HelpKpis?> fetchKpis({
    String scope = 'own',
    String period = 'month',
    String? from,
    String? to,
  }) async {
    try {
      final body = await _api.get(
        ApiEndpoints.dashboardIssueKpis,
        query: _query(scope, period, from, to),
      );
      return HelpKpis.fromJson(body);
    } on Object {
      return null;
    }
  }

  /// `GET /crm/dashboard-issue/sla-priority-mix/` — the two donuts (§3).
  ///
  /// Best-effort like the KPIs: null on any failure, and the card falls back to
  /// counting the loaded tickets.
  Future<SlaPriorityMix?> fetchSlaPriorityMix({
    String scope = 'own',
    String period = 'month',
    String? from,
    String? to,
  }) async {
    try {
      final body = await _api.get(ApiEndpoints.dashboardIssueSlaPriorityMix,
          query: _query(scope, period, from, to));
      return SlaPriorityMix.fromJson(body);
    } on Object {
      return null;
    }
  }

  /// `GET /crm/dashboard-issue/tickets-completed-grid/` — priority × on-time
  /// (§9). Null on failure; empty list is a real "nothing completed".
  Future<List<CompletedGridRow>?> fetchCompletedGrid({
    String scope = 'own',
    String period = 'month',
    String? from,
    String? to,
  }) async {
    try {
      final body = await _api.get(ApiEndpoints.dashboardIssueCompletedGrid,
          query: _query(scope, period, from, to));
      return CompletedGridRow.listFrom(body);
    } on Object {
      return null;
    }
  }
}
