import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/models/note.dart';
import '../../../notes/application/providers/notes_providers.dart';
import '../../../notes/domain/repositories/notes_repository.dart';

/// Seed descriptor for a record's notes thread (#13). Equality is keyed purely
/// on [recordId] so the same record always resolves to the same notifier —
/// [build] runs only once, when the notifier is first created. Each detail
/// screen supplies its own seed (via-tagged lead/customer notes, plain
/// follow-up/task notes) without this provider needing to know the record type.
class CrmNotesSeed {
  const CrmNotesSeed(this.recordId, this.build, {this.apiModel});

  final String recordId;
  final List<NoteEntry> Function() build;

  /// The API `related_to` model for this thread (`lead` / `customer` /
  /// `task` — follow-ups pass `task` too). Null = remote notes are not wired
  /// for this record; the thread stays local-only even in API mode.
  final String? apiModel;

  /// The uuid to pass as `related_to_id` — [recordId] minus the local
  /// `TASK-` / `FU-` prefixes the detail screens use to namespace threads.
  String get apiRecordId {
    if (recordId.startsWith('TASK-')) return recordId.substring(5);
    if (recordId.startsWith('FU-')) return recordId.substring(3);
    return recordId;
  }

  @override
  bool operator ==(Object other) => other is CrmNotesSeed && other.recordId == recordId;

  @override
  int get hashCode => recordId.hashCode;
}

/// Owns a single record's live notes list. The composer prepends new notes and
/// appends replies; both usable regardless of the record's locked/converted
/// state (the composer is never gated).
///
/// In API mode ([CrmNotesNotifier.remote]) the thread seeds by fetching the
/// record's remote notes through the shared [NotesRepository], and every add is
/// optimistic: the local entry shows immediately, the POST fires in the
/// background, and a failure keeps the optimistic entry (no error surface on the
/// notes panel).
class CrmNotesNotifier extends StateNotifier<List<NoteEntry>> {
  CrmNotesNotifier(List<NoteEntry> seed)
      : _repo = null,
        _apiModel = null,
        _apiRecordId = '',
        super(List.of(seed));

  CrmNotesNotifier.remote(NotesRepository repo, CrmNotesSeed seed)
      : _repo = repo,
        _apiModel = seed.apiModel,
        _apiRecordId = seed.apiRecordId,
        super(const []) {
    _load();
  }

  final NotesRepository? _repo;
  final String? _apiModel;
  final String _apiRecordId;

  int _seq = 0;

  bool get _remoteWired =>
      _repo != null && _apiModel != null && _apiRecordId.isNotEmpty;

  Future<void> _load() async {
    if (!_remoteWired) return;
    try {
      final fetched = await _repo!.fetchNotes(_apiModel!, _apiRecordId);
      if (mounted) state = fetched;
    } on Object {
      // Offline / error → the panel simply starts empty; adds still work
      // optimistically.
    }
  }

  /// Prepends a note authored by [author] with any pending [attachments].
  void addNote(String body, List<NoteAttachment> attachments, NoteAuthor author) {
    final localId = 'note-new-${_seq++}';
    state = [
      NoteEntry(
        id: localId,
        author: author.name,
        time: 'Just now',
        body: body,
        avatarColor: author.color,
        attachments: attachments,
      ),
      ...state,
    ];
    if (!_remoteWired) return;
    unawaited(() async {
      try {
        final created = await _repo!.addNote(
          relatedTo: _apiModel!,
          relatedToId: _apiRecordId,
          body: body,
        );
        if (created == null || !mounted) return;
        // Attachments are a second call — the upload points at a note_id, so
        // it can only happen now that the note exists.
        final uploaded = await _uploadAttachments(created.id, attachments);
        if (!mounted) return;
        // Swap in the server id so replies to this note hit the real thread.
        state = [
          for (final n in state)
            n.id == localId
                ? NoteEntry(
                    id: created.id,
                    author: n.author,
                    time: n.time,
                    body: n.body,
                    via: n.via,
                    avatarColor: n.avatarColor,
                    replies: n.replies,
                    attachments: uploaded,
                  )
                : n,
        ];
      } on Object {
        // Keep the optimistic entry.
      }
    }());
  }

  /// Uploads each pending file against [noteId], one at a time.
  ///
  /// Returns the attachments to display: an upload that succeeds swaps in its
  /// hosted url, one that fails keeps the local entry so the chip does not
  /// vanish from a note the user can see. Sequential rather than parallel —
  /// these are phone uploads on a mobile connection, and a burst of them
  /// competes for the same bandwidth.
  Future<List<NoteAttachment>> _uploadAttachments(
    String noteId,
    List<NoteAttachment> attachments,
  ) async {
    if (attachments.isEmpty) return attachments;
    final out = <NoteAttachment>[];
    for (final a in attachments) {
      if (!a.isPending) {
        out.add(a);
        continue;
      }
      try {
        out.add(await _repo!.addAttachment(noteId: noteId, attachment: a) ?? a);
      } on Object {
        out.add(a); // upload failed — keep showing what the user attached
      }
    }
    return out;
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
    // Only sync replies on notes that exist server-side (uuid ids); a reply on
    // a still-local optimistic note stays local.
    if (!_remoteWired || noteId.startsWith('note-new-')) return;
    unawaited(() async {
      try {
        await _repo!.addReply(noteId: noteId, body: body);
      } on Object {
        // Keep the optimistic reply.
      }
    }());
  }
}

/// Per-record notes provider. Kept alive (no autoDispose) so notes added on a
/// detail screen survive navigation away and back.
final crmNotesProvider =
    StateNotifierProvider.family<CrmNotesNotifier, List<NoteEntry>, CrmNotesSeed>(
  (ref, seed) {
    if (ApiConfig.apiEnabled) {
      return CrmNotesNotifier.remote(ref.read(notesRepositoryProvider), seed);
    }
    return CrmNotesNotifier(seed.build());
  },
);
