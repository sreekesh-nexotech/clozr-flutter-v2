import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/models/note.dart';
import 'package:clozrapp/features/helpdesk/application/providers/ticket_notes_providers.dart';

/// Any author will do here — these tests are about thread behaviour, not the
/// byline. The real one comes from `noteAuthorProvider`.
const _author = NoteAuthor(initials: 'TU', name: 'Test User', color: Color(0xFF00113B));

void main() {
  group('TicketNotesController (mock mode — no remote wired)', () {
    test('seeds the two prototype sample notes', () {
      final c = TicketNotesController('TKT-1024', _author);
      expect(c.state, hasLength(2));
      expect(c.state.first.author, 'Divya Raj');
      expect(c.state.first.via, 'Call');
      expect(c.state.first.replies, hasLength(1));
    });

    test('addNote prepends an optimistic internal note', () {
      final c = TicketNotesController('TKT-1024', _author);
      c.addNote('Rework scheduled for Monday', const []);
      expect(c.state, hasLength(3));
      // Bylined with whoever the controller was given — it used to be a
      // hardcoded prototype user regardless of who was signed in.
      expect(c.state.first.author, _author.name);
      expect(c.state.first.body, 'Rework scheduled for Monday');
      expect(c.state.first.time, 'Just now');
    });

    test('addNote ignores an empty note with no attachments', () {
      final c = TicketNotesController('TKT-1024', _author);
      c.addNote('   ', const []);
      expect(c.state, hasLength(2));
    });

    test('addReply appends a reply to the target note', () {
      final c = TicketNotesController('TKT-1024', _author);
      final seededNoteId = c.state[1].id; // 'tnote-...-seed-1' (no replies yet)
      c.addReply(seededNoteId, 'Confirmed with the crew');
      final updated = c.state.firstWhere((NoteEntry n) => n.id == seededNoteId);
      expect(updated.replies, hasLength(1));
      expect(updated.replies.last.body, 'Confirmed with the crew');
      expect(updated.replies.last.author, _author.name);
    });
  });
}
