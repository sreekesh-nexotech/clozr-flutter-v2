import '../../domain/entities/dashboard_models.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../data_sources/local/dashboard_mock_ds.dart';

/// Mock-backed dashboard repository: serves the seeded bundle regardless of
/// period/team so mock mode behaves exactly as the presentation build did.
class DashboardRepositoryImpl implements DashboardRepository {
  const DashboardRepositoryImpl(this._ds);
  final DashboardMockDataSource _ds;

  @override
  Future<DashboardData> getDashboard(
          {String period = 'month', String? teamId, String? userId}) async =>
      _ds.load();
}
