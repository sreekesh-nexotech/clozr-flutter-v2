import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/models/note.dart';
import 'ops_tasks_providers.dart';

/// Stateful notes thread for a single Operations record (#13). Holds the shared
/// [NoteEntry] list the core `NotesThread` renders; new notes prepend and replies
/// append. Seeded once from the record's mock notes and kept in memory for the
/// session (a real API-backed store slots in behind the same interface).
class OpsNotesNotifier extends StateNotifier<List<NoteEntry>> {
  OpsNotesNotifier(List<NoteEntry> seed) : super(seed);

  static const _me = NoteAuthor();

  void addNote(String body, List<NoteAttachment> attachments) {
    final entry = NoteEntry(
      id: 'note-${DateTime.now().microsecondsSinceEpoch}',
      author: _me.name,
      time: 'now',
      body: body,
      avatarColor: _me.color,
      attachments: attachments,
    );
    state = [entry, ...state];
  }

  void addReply(String noteId, String body) {
    final next = <NoteEntry>[];
    for (final n in state) {
      if (n.id == noteId) {
        n.replies.add(NoteReply(author: _me.name, time: 'now', body: body, avatarColor: _me.color));
      }
      next.add(n);
    }
    state = next;
  }
}

NoteEntry _fromOpsNote(String recordId, int i, dynamic n) => NoteEntry(
      id: 'seed-$recordId-$i',
      author: n.author as String,
      time: n.time as String,
      body: n.body as String,
      avatarColor: AppColors.navy,
    );

/// Notes for a project / ops-task detail, keyed by record id. Task records seed
/// from their mock notes; projects (no seeded notes) start empty.
final opsNotesProvider =
    StateNotifierProvider.family<OpsNotesNotifier, List<NoteEntry>, String>((ref, id) {
  final task = ref.read(opsTaskByIdProvider(id));
  final seed = <NoteEntry>[];
  if (task != null) {
    for (var i = 0; i < task.notes.length; i++) {
      seed.add(_fromOpsNote(id, i, task.notes[i]));
    }
  }
  return OpsNotesNotifier(seed);
});

/// Subtask-local notes, keyed by `"<taskId>#<index>"`. In-memory only.
final subtaskNotesProvider =
    StateNotifierProvider.family<OpsNotesNotifier, List<NoteEntry>, String>((ref, key) {
  return OpsNotesNotifier(<NoteEntry>[]);
});
