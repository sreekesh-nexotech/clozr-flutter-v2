import '../entities/project.dart';

/// Abstract contract for project data. The presentation layer depends only on
/// this; whether projects come from a mock source or a REST API is an
/// infrastructure detail.
abstract class ProjectsRepository {
  Future<List<Project>> getProjects();

  /// Creates a project from API-shaped [fields] (`project_name`, `priority`,
  /// `description`, `expected_end_date`, …). Returns the created project when
  /// the backend echoes a usable row, null otherwise (mock mode always null).
  Future<Project?> createProject(Map<String, dynamic> fields);

  /// Partially updates project [id] with API-shaped [fields].
  Future<void> updateProject(String id, Map<String, dynamic> fields);
}
