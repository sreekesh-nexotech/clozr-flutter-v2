import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../crm/domain/entities/lead_file.dart';
import '../entities/project.dart';

/// Abstract contract for project data. The presentation layer depends only on
/// this; whether projects come from a mock source or a REST API is an
/// infrastructure detail.
abstract class ProjectsRepository {
  /// [filters] are `/projects/projects/` query params from the drawer, the
  /// status tabs and the My-projects toggle, applied server-side.
  Future<List<Project>> getProjects({Map<String, dynamic> filters = const {}});

  /// Per-status tab counts under the same [filters] as the list (§2), keyed by
  /// status name plus `'all'`. Empty means "no counts" — count locally.
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters);

  /// The org's project statuses (`operations.md` §3) — the tab strip and the
  /// drawer's Status facet. Empty means "no catalog".
  Future<List<CatalogOption>> getProjectStatuses();

  /// The org's project types (§4) — the drawer's Type facet.
  Future<List<CatalogOption>> getProjectTypes();

  /// Creates a project from API-shaped [fields] (`project_name`, `priority`,
  /// `description`, `expected_end_date`, …). Returns the created project when
  /// the backend echoes a usable row, null otherwise (mock mode always null).
  Future<Project?> createProject(Map<String, dynamic> fields);

  /// Partially updates project [id] with API-shaped [fields].
  Future<void> updateProject(String id, Map<String, dynamic> fields);

  /// One project in its **full shape** — the costing, assignees, team,
  /// visibility and progress method the list's slim rows drop.
  ///
  /// Null when unavailable (mock mode, a failed call); the caller keeps the
  /// list row it already has.
  Future<Project?> getProject(String id);

  /// The project's attachments — the Files tab (`operations.md` §15).
  Future<List<LeadFile>> getProjectAttachments(String projectId);

  /// Uploads one picked file to a project's Files tab. Throws when the backend
  /// refuses, so the caller can say why rather than reporting a success.
  Future<void> uploadProjectAttachment({
    required String projectId,
    required String path,
    required String name,
  });

  /// Archives [id], or restores it with `archive: false`.
  ///
  /// Throws on refusal — restoring into a name an active project already holds
  /// is a 400, and that has to reach the user.
  Future<void> archiveProject(String id, {required bool archive});
}
