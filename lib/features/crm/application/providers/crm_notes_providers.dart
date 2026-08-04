import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/models/note.dart';
import '../../../../core/network/network_providers.dart';
import '../../infrastructure/data_sources/remote/crm_notes_remote_ds.dart';

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
/// record's remote notes, and every add is optimistic: the local entry shows
/// immediately, the POST fires in the background, and a failure keeps the
/// optimistic entry (no error surface on the notes panel).
class CrmNotesNotifier extends StateNotifier<List<NoteEntry>> {
  CrmNotesNotifier(List<NoteEntry> seed)
      : _remote = null,
        _apiModel = null,
        _apiRecordId = '',
        super(List.of(seed));

  CrmNotesNotifier.remote(CrmNotesRemoteDataSource remote, CrmNotesSeed seed)
      : _remote = remote,
        _apiModel = seed.apiModel,
        _apiRecordId = seed.apiRecordId,
        super(const []) {
    _load();
  }

  final CrmNotesRemoteDataSource? _remote;
  final String? _apiModel;
  final String _apiRecordId;

  int _seq = 0;

  bool get _remoteWired =>
      _remote != null && _apiModel != null && _apiRecordId.isNotEmpty;

  Future<void> _load() async {
    if (!_remoteWired) return;
    try {
      final fetched = await _remote!.fetchNotes(_apiModel!, _apiRecordId);
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
        final created = await _remote!.addNote(_apiModel!, _apiRecordId, body);
        if (created == null || !mounted) return;
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
                    attachments: n.attachments,
                  )
                : n,
        ];
      } on Object {
        // Keep the optimistic entry.
      }
    }());
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
        await _remote!.addReply(noteId, body);
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
      return CrmNotesNotifier.remote(
        CrmNotesRemoteDataSource(ref.watch(apiServiceProvider)),
        seed,
      );
    }
    return CrmNotesNotifier(seed.build());
  },
);
