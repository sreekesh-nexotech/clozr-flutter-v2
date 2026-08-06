import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/models/note.dart';
import '../../../notes/application/providers/notes_providers.dart';
import '../../../notes/domain/repositories/notes_repository.dart';

/// Per-ticket Notes store (#13). Keyed by ticket id.
///
/// In **mock mode** the thread seeds from [_seed] so each ticket reads as a live
/// conversation (the prototype behaviour, unchanged). In **API mode** the seed
/// is dropped entirely (audit L-5): the thread starts empty, fetches the ticket's
/// real notes from `/crm/notes/?related_to=issue&related_to_id=<ticketId>`, and
/// every add is optimistic — the local entry shows immediately, the POST fires
/// in the background, and the server id is swapped in on success (so replies hit
/// the real thread). Goes through the shared [NotesRepository]: helpdesk notes
/// live on the same `/crm/notes/` endpoint, tagged `related_to=issue`.
class TicketNotesController extends StateNotifier<List<NoteEntry>> {
  /// Mock-mode: seed the prototype's fixed sample notes.
  TicketNotesController(this.ticketId)
      : _repo = null,
        super(_seed(ticketId));

  /// API-mode: start empty, then load the ticket's real notes.
  TicketNotesController.remote(NotesRepository repo, this.ticketId)
      : _repo = repo,
        super(const []) {
    _load();
  }

  final String ticketId;
  final NotesRepository? _repo;

  /// The signed-in author — mirrors [NotesThread]'s default "MV" Manoj Varma.
  static const _me = NoteAuthor();

  int _seq = 0;

  bool get _remoteWired => _repo != null && ticketId.isNotEmpty;

  Future<void> _load() async {
    if (!_remoteWired) return;
    try {
      final fetched = await _repo!.fetchNotes('issue', ticketId);
      if (mounted) state = fetched;
    } on Object {
      // Offline / error → the panel simply starts empty; adds still work
      // optimistically.
    }
  }

  void addNote(String body, List<NoteAttachment> attachments) {
    if (body.trim().isEmpty && attachments.isEmpty) return;
    final localId = 'tnote-$ticketId-${_seq++}-${DateTime.now().microsecondsSinceEpoch}';
    state = [
      NoteEntry(
        id: localId,
        author: _me.name,
        time: 'Just now',
        body: body.trim(),
        avatarColor: _me.color,
        attachments: attachments,
      ),
      ...state,
    ];
    if (!_remoteWired) return;
    unawaited(() async {
      try {
        final created = await _repo!.addNote(
          relatedTo: 'issue',
          relatedToId: ticketId,
          body: body.trim(),
        );
        if (created == null || !mounted) return;
        // Attachments upload against the created note, so only now.
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

  /// Uploads each pending file against [noteId]. A failed upload keeps the
  /// local chip rather than dropping it from a note already on screen.
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
        out.add(a);
      }
    }
    return out;
  }

  void addReply(String noteId, String body) {
    if (body.trim().isEmpty) return;
    state = [
      for (final n in state)
        if (n.id == noteId)
          NoteEntry(
            id: n.id,
            author: n.author,
            time: n.time,
            body: n.body,
            via: n.via,
            avatarColor: n.avatarColor,
            attachments: n.attachments,
            replies: [
              ...n.replies,
              NoteReply(author: _me.name, time: 'Just now', body: body.trim(), avatarColor: _me.color),
            ],
          )
        else
          n,
    ];
    // Only sync replies on notes that exist server-side (uuid ids); a reply on a
    // still-local optimistic/seeded note (`tnote-` prefix) stays local.
    if (!_remoteWired || noteId.startsWith('tnote-')) return;
    unawaited(() async {
      try {
        await _repo!.addReply(noteId: noteId, body: body.trim());
      } on Object {
        // Keep the optimistic reply.
      }
    }());
  }
}

/// Mutable Notes thread for a single ticket, keyed by ticket id. API-backed when
/// a base URL is configured, mock-seeded otherwise.
final ticketNotesProvider =
    StateNotifierProvider.family<TicketNotesController, List<NoteEntry>, String>(
  (ref, ticketId) {
    if (ApiConfig.apiEnabled) {
      return TicketNotesController.remote(ref.read(notesRepositoryProvider), ticketId);
    }
    return TicketNotesController(ticketId);
  },
);

/// Seed notes. Presentation-layer mock — a couple of realistic entries so the
/// thread reads as a live conversation rather than an empty shell.
List<NoteEntry> _seed(String ticketId) => [
      NoteEntry(
        id: 'tnote-$ticketId-seed-0',
        author: 'Divya Raj',
        time: 'Yesterday, 4:20 PM',
        body: 'Logged the customer call — they want confirmation before the crew is scheduled. '
            'Flagged to the fit-out lead.',
        via: 'Call',
        avatarColor: AppColors.pending,
        replies: [
          NoteReply(
            author: 'Manoj Varma',
            time: 'Yesterday, 4:45 PM',
            body: 'Thanks — I’ll follow up on email and keep this open until we hear back.',
            avatarColor: AppColors.navy,
          ),
        ],
      ),
      NoteEntry(
        id: 'tnote-$ticketId-seed-1',
        author: 'Manoj Varma',
        time: '2 days ago',
        body: 'Internal: confirmed SLA target with the team. No blockers on our side.',
        avatarColor: AppColors.navy,
      ),
    ];
