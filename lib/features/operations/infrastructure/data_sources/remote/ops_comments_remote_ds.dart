import '../../../../../core/models/note.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';

/// The Operations comment thread — `/projects/comments/`.
///
/// A project task's notes are **not** CRM Notes: `/crm/notes/` refuses a
/// projects task outright (`"Invalid task ID or access denied"` — its `task`
/// model is the CRM interaction task, a different table). `operations-task.md`
/// §3 names this collection as what `comment_count` counts, and it is the one
/// that accepts a `task_id`.
///
/// Mind the asymmetry, both verified against the dev backend: **writes** take
/// `related_to: "project_task"` (`"task"` is rejected — *"Must be one of:
/// project, project_task"*), while **reads** filter on `related_to=task`.
class OpsCommentsRemoteDataSource {
  const OpsCommentsRemoteDataSource(this._api);

  final ApiService _api;

  static const String _path = '/projects/comments/';

  /// The thread on one task or project, newest first.
  Future<List<NoteEntry>> fetch({
    required String recordId,
    bool isProject = false,
  }) async {
    if (recordId.isEmpty) return const [];
    final body = await _api.get(_path, query: {
      // Reads use the bare model name; writes use the prefixed one.
      'related_to': isProject ? 'project' : 'task',
      'related_to_id': recordId,
      'page_size': 100,
    });
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    return [for (final row in rows) noteFromComment(row)];
  }

  /// Posts one comment. Returns the mapped row so the caller can swap its
  /// optimistic entry for the stored one.
  Future<NoteEntry?> add({
    required String recordId,
    required String body,
    bool isProject = false,
  }) async {
    final res = await _api.post(_path, body: {
      'related_to': isProject ? 'project' : 'project_task',
      'related_to_id': recordId,
      'content': body,
    });
    return res is Map<String, dynamic> ? noteFromComment(res) : null;
  }

  /// One `/projects/comments/` row → the shared [NoteEntry] the notes thread
  /// renders. Replies are not a concept here, so every row is top-level.
  static NoteEntry noteFromComment(Map<String, dynamic> row) {
    final at = parseApiDate(row['created_at']);
    return NoteEntry(
      id: (row['comment_id'] ?? '').toString(),
      author: (row['created_by_name'] ?? '').toString().trim().isEmpty
          ? 'Unknown'
          : row['created_by_name'].toString(),
      time: at == null ? '' : relativeTime(at),
      body: (row['content'] ?? '').toString(),
    );
  }
}
