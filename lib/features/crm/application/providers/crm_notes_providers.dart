import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/note.dart';

/// Seed descriptor for a record's notes thread (#13). Equality is keyed purely
/// on [recordId] so the same record always resolves to the same notifier —
/// [build] runs only once, when the notifier is first created. Each detail
/// screen supplies its own seed (via-tagged lead/customer notes, plain
/// follow-up/task notes) without this provider needing to know the record type.
class CrmNotesSeed {
  const CrmNotesSeed(this.recordId, this.build);

  final String recordId;
  final List<NoteEntry> Function() build;

  @override
  bool operator ==(Object other) => other is CrmNotesSeed && other.recordId == recordId;

  @override
  int get hashCode => recordId.hashCode;
}

/// Owns a single record's live notes list. The composer prepends new notes and
/// appends replies; both usable regardless of the record's locked/converted
/// state (the composer is never gated).
class CrmNotesNotifier extends StateNotifier<List<NoteEntry>> {
  CrmNotesNotifier(List<NoteEntry> seed) : super(List.of(seed));

  int _seq = 0;

  /// Prepends a note authored by [author] with any pending [attachments].
  void addNote(String body, List<NoteAttachment> attachments, NoteAuthor author) {
    state = [
      NoteEntry(
        id: 'note-new-${_seq++}',
        author: author.name,
        time: 'Just now',
        body: body,
        avatarColor: author.color,
        attachments: attachments,
      ),
      ...state,
    ];
  }

  /// Appends a reply to the note identified by [noteId].
  void addReply(String noteId, String body, NoteAuthor author) {
    for (final n in state) {
      if (n.id == noteId) {
        n.replies.add(NoteReply(
          author: author.name,
          time: 'Just now',
          body: body,
          avatarColor: author.color,
        ));
        break;
      }
    }
    // Reassign to a fresh reference so listeners rebuild.
    state = List.of(state);
  }
}

/// Per-record notes provider. Kept alive (no autoDispose) so notes added on a
/// detail screen survive navigation away and back.
final crmNotesProvider =
    StateNotifierProvider.family<CrmNotesNotifier, List<NoteEntry>, CrmNotesSeed>(
  (ref, seed) => CrmNotesNotifier(seed.build()),
);
