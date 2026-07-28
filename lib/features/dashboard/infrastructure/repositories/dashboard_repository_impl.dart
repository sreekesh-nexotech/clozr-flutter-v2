import '../../domain/entities/dashboard_models.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../data_sources/local/dashboard_mock_ds.dart';

/// Mock-backed dashboard repository. Replace [DashboardMockDataSource] with a
/// remote source when `/dashboard` lands; the panels are unaffected.
class DashboardRepositoryImpl implements DashboardRepository {
  const DashboardRepositoryImpl(this._ds);
  final DashboardMockDataSource _ds;

  @override
  DashboardData getDashboard() => _ds.load();
}
