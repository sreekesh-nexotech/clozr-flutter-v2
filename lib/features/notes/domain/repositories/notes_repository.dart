import '../../../../core/models/note.dart';

/// Abstract contract for a record's Notes thread, shared across every module
/// (CRM leads/customers/tasks, helpdesk tickets, …). The application layer
/// depends only on this; whether notes come from the REST API or an inert mock
/// stub is an infrastructure detail.
abstract class NotesRepository {
  /// Top-level notes for one record, newest-first. `relatedTo` is the API model
  /// (`lead` / `customer` / `task` / `issue`); replies load lazily, so entries
  /// come back with empty `replies`.
  Future<List<NoteEntry>> fetchNotes(String relatedTo, String relatedToId);

  /// Creates a top-level note; returns the mapped created row, or null when the
  /// backend response shape is unexpected (the caller keeps its optimistic
  /// entry).
  Future<NoteEntry?> addNote({
    required String relatedTo,
    required String relatedToId,
    required String body,
  });

  /// Posts a reply under [noteId]; returns the mapped reply, or null on failure.
  Future<NoteReply?> addReply({
    required String noteId,
    required String body,
  });
}
