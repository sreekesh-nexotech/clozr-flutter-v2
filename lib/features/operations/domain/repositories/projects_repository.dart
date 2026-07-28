import '../entities/project.dart';

/// Abstract contract for project data. The presentation layer depends only on
/// this; whether projects come from a mock source or a REST API is an
/// infrastructure detail.
abstract class ProjectsRepository {
  Future<List<Project>> getProjects();
}
