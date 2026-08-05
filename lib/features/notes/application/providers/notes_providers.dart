import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/models/note.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/repositories/notes_repository.dart';
import '../../infrastructure/data_sources/remote/notes_remote_ds.dart';
import '../../infrastructure/repositories/notes_api_repository.dart';

/// DI seam for the shared Notes repository. API-backed when a base URL is
/// configured; an inert no-op stub otherwise. The stub is never exercised — in
/// mock mode the notes notifiers serve their local seed and never call the repo.
final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  return ApiConfig.apiEnabled
      ? NotesApiRepository(NotesRemoteDataSource(ref.watch(apiServiceProvider)))
      : const _NoopNotesRepository();
});

/// Inert [NotesRepository] used in mock mode. Returns empty/null for every call;
/// the notes notifiers never reach it because they build from their local seed.
class _NoopNotesRepository implements NotesRepository {
  const _NoopNotesRepository();

  @override
  Future<List<NoteEntry>> fetchNotes(String relatedTo, String relatedToId) async =>
      const [];

  @override
  Future<NoteEntry?> addNote({
    required String relatedTo,
    required String relatedToId,
    required String body,
  }) async =>
      null;

  @override
  Future<NoteReply?> addReply({
    required String noteId,
    required String body,
  }) async =>
      null;
}
