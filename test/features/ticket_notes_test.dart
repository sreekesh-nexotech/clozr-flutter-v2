import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/models/note.dart';
import 'package:clozrapp/features/helpdesk/application/providers/ticket_notes_providers.dart';

void main() {
  group('TicketNotesController (mock mode — no remote wired)', () {
    test('seeds the two prototype sample notes', () {
      final c = TicketNotesController('TKT-1024');
      expect(c.state, hasLength(2));
      expect(c.state.first.author, 'Divya Raj');
      expect(c.state.first.via, 'Call');
      expect(c.state.first.replies, hasLength(1));
    });

    test('addNote prepends an optimistic internal note', () {
      final c = TicketNotesController('TKT-1024');
      c.addNote('Rework scheduled for Monday', const []);
      expect(c.state, hasLength(3));
      expect(c.state.first.author, 'Manoj Varma');
      expect(c.state.first.body, 'Rework scheduled for Monday');
      expect(c.state.first.time, 'Just now');
    });

    test('addNote ignores an empty note with no attachments', () {
      final c = TicketNotesController('TKT-1024');
      c.addNote('   ', const []);
      expect(c.state, hasLength(2));
    });

    test('addReply appends a reply to the target note', () {
      final c = TicketNotesController('TKT-1024');
      final seededNoteId = c.state[1].id; // 'tnote-...-seed-1' (no replies yet)
      c.addReply(seededNoteId, 'Confirmed with the crew');
      final updated = c.state.firstWhere((NoteEntry n) => n.id == seededNoteId);
      expect(updated.replies, hasLength(1));
      expect(updated.replies.last.body, 'Confirmed with the crew');
      expect(updated.replies.last.author, 'Manoj Varma');
    });
  });
}
