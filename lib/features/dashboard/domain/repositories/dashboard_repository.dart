import '../entities/dashboard_models.dart';

/// Read seam for the manager/admin dashboard bundle. Swap the implementation to
/// an API-backed source without touching the panels.
abstract class DashboardRepository {
  DashboardData getDashboard();
}
