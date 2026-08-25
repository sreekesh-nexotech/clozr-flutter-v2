import '../../../../app/config/constants.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../crm/domain/entities/lead_file.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/projects_repository.dart';
import '../data_sources/local/projects_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class ProjectsRepositoryImpl implements ProjectsRepository {
  const ProjectsRepositoryImpl(this._local);

  final ProjectsMockDataSource _local;

  @override
  Future<List<Project>> getProjects({Map<String, dynamic> filters = const {}}) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchProjects();
  }

  /// Mock writes are harmless no-ops: mock-mode screens keep their local
  /// toast-and-pop behavior and never read the result.
  @override
  Future<Project?> createProject(Map<String, dynamic> fields) async => null;

  @override
  Future<void> updateProject(String id, Map<String, dynamic> fields) async {}

  /// No retrieve endpoint in mock mode; the seed row is all there is.
  @override
  Future<Project?> getProject(String id) async => null;

  @override
  Future<List<LeadFile>> getProjectAttachments(String projectId) async => const [];

  /// Mock write: no-op — there is no store to upload into.
  @override
  Future<void> uploadProjectAttachment({
    required String projectId,
    required String path,
    required String name,
  }) async {}

  /// Nothing to archive against; the screen's toast is the whole behaviour.
  @override
  Future<void> archiveProject(String id, {required bool archive}) async {}

  /// Mock mode has no org catalogs; the drawer falls back to the built-ins.
  @override
  Future<List<CatalogOption>> getProjectStatuses() async => const [];

  /// No aggregate in mock mode; the tab strip counts the seed rows itself.
  @override
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters) async => const {};

  @override
  Future<List<CatalogOption>> getProjectTypes() async => const [];
}
