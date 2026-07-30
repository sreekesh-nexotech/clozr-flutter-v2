import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/models/note.dart';

/// Per-ticket Notes store (#13). Keyed by ticket id and seeded from mock notes so
/// each ticket keeps its own thread. `addNote` prepends a fresh [NoteEntry] (an
/// internal note); `addReply` appends a [NoteReply] to the target note.
///
/// API-ready: swap [_seed] for a repository call when `/tickets/{id}/notes`
/// lands and the UI is unchanged.
class TicketNotesController extends StateNotifier<List<NoteEntry>> {
  TicketNotesController(this.ticketId) : super(_seed(ticketId));

  final String ticketId;

  /// The signed-in author — mirrors [NotesThread]'s default "MV" Manoj Varma.
  static const _me = NoteAuthor();

  int _seq = 0;

  void addNote(String body, List<NoteAttachment> attachments) {
    if (body.trim().isEmpty && attachments.isEmpty) return;
    state = [
      NoteEntry(
        id: 'tnote-$ticketId-${_seq++}-${DateTime.now().microsecondsSinceEpoch}',
        author: _me.name,
        time: 'Just now',
        body: body.trim(),
        avatarColor: _me.color,
        attachments: attachments,
      ),
      ...state,
    ];
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
  }
}

/// Mutable Notes thread for a single ticket, keyed by ticket id.
final ticketNotesProvider =
    StateNotifierProvider.family<TicketNotesController, List<NoteEntry>, String>(
  (ref, ticketId) => TicketNotesController(ticketId),
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
