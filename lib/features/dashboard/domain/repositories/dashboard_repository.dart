import '../entities/dashboard_models.dart';

/// Read seam for the manager/admin dashboard bundle. Swap the implementation to
/// an API-backed source without touching the panels.
///
/// [period] is the API period value (`month`, `last_month`, `ytd`, …) and
/// [teamId] the selected team uuid (`'all'` / null → org-wide).
abstract class DashboardRepository {
  Future<DashboardData> getDashboard(
      {String period = 'month', String? teamId, String? userId});
}
