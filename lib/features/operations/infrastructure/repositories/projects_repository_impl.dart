import '../../../../app/config/constants.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/projects_repository.dart';
import '../data_sources/local/projects_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class ProjectsRepositoryImpl implements ProjectsRepository {
  const ProjectsRepositoryImpl(this._local);

  final ProjectsMockDataSource _local;

  @override
  Future<List<Project>> getProjects() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchProjects();
  }

  /// Mock writes are harmless no-ops: mock-mode screens keep their local
  /// toast-and-pop behavior and never read the result.
  @override
  Future<Project?> createProject(Map<String, dynamic> fields) async => null;

  @override
  Future<void> updateProject(String id, Map<String, dynamic> fields) async {}
}
