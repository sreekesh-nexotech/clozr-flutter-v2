import '../../../../core/models/note.dart';
import '../../domain/repositories/notes_repository.dart';
import '../data_sources/remote/notes_remote_ds.dart';

/// API-backed [NotesRepository] over `/crm/notes/`. A thin pass-through to
/// [NotesRemoteDataSource] — the notes notifiers own state, seeding and
/// optimism, so there is nothing to cache or reshape here.
class NotesApiRepository implements NotesRepository {
  const NotesApiRepository(this._remote);

  final NotesRemoteDataSource _remote;

  @override
  Future<List<NoteEntry>> fetchNotes(String relatedTo, String relatedToId) =>
      _remote.fetchNotes(relatedTo, relatedToId);

  @override
  Future<NoteEntry?> addNote({
    required String relatedTo,
    required String relatedToId,
    required String body,
  }) =>
      _remote.addNote(relatedTo, relatedToId, body);

  @override
  Future<NoteReply?> addReply({
    required String noteId,
    required String body,
  }) =>
      _remote.addReply(noteId, body);
}
