// Note pinning. The backend has always stored `is_pinned`; nothing in the app
// read or wrote it, so there was no pin control and a pinned note sorted purely
// by recency like any other.
//
// Two things are easy to get wrong here and both are covered below:
//
// * `is_pinned` arrives as an **integer** (0/1), not a bool. A plain `== true`
//   reads every pinned note as unpinned, and PATCHing a bool is rejected with
//   `{"is_pinned": ["A valid integer is required."]}`.
// * the list endpoint orders by recency only and ignores `?ordering=-is_pinned`,
//   so "pinned stays on top" has to be done client-side.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/models/note.dart';
import 'package:clozrapp/features/crm/application/providers/crm_notes_providers.dart';
import 'package:clozrapp/features/notes/infrastructure/data_sources/remote/notes_remote_ds.dart';

NoteEntry _note(String id, {bool pinned = false}) => NoteEntry(
      id: id,
      author: 'Someone',
      time: '1 Jan',
      body: 'body $id',
      pinned: pinned,
    );

void main() {
  group('is_pinned mapping', () {
    // The field is an integer column; 1/0 is what actually comes back.
    test('1 and 0 map to pinned and unpinned', () {
      expect(NotesRemoteDataSource.noteFromJson(const {
        'note_id': 'n1',
        'content': 'x',
        'is_pinned': 1,
      })!.pinned, isTrue);

      expect(NotesRemoteDataSource.noteFromJson(const {
        'note_id': 'n2',
        'content': 'x',
        'is_pinned': 0,
      })!.pinned, isFalse);
    });

    test('a missing field is not pinned, and a real bool still works', () {
      expect(NotesRemoteDataSource.noteFromJson(const {
        'note_id': 'n3',
        'content': 'x',
      })!.pinned, isFalse);

      // Tolerated in case the serializer is ever changed to a proper bool.
      expect(NotesRemoteDataSource.noteFromJson(const {
        'note_id': 'n4',
        'content': 'x',
        'is_pinned': true,
      })!.pinned, isTrue);
    });
  });

  group('thread ordering', () {
    test('pinning moves a note to the top even when it is the oldest', () {
      // `newer` leads on recency, as the API returns it.
      final notifier = CrmNotesNotifier([_note('newer'), _note('older')]);
      expect([for (final n in notifier.state) n.id], ['newer', 'older']);

      notifier.togglePin('older');

      expect([for (final n in notifier.state) n.id], ['older', 'newer'],
          reason: 'a pinned note leads regardless of its date');
      expect(notifier.state.first.pinned, isTrue);
      expect(notifier.state.last.pinned, isFalse);
    });

    test('unpinning clears the flag', () {
      final notifier = CrmNotesNotifier([_note('a', pinned: true), _note('b')]);
      notifier.togglePin('a');
      expect(notifier.state.firstWhere((n) => n.id == 'a').pinned, isFalse);
    });

    test('a second pin joins the pinned group without reshuffling it', () {
      final notifier = CrmNotesNotifier(
          [_note('one'), _note('two'), _note('three')]);

      notifier.togglePin('three');
      expect([for (final n in notifier.state) n.id], ['three', 'one', 'two']);

      notifier.togglePin('two');
      // The partition is stable, so `three` — already promoted — stays ahead of
      // `two` rather than the newest pin jumping the queue.
      expect([for (final n in notifier.state) n.id], ['three', 'two', 'one']);
      expect(notifier.state.take(2).every((n) => n.pinned), isTrue);
    });

    test('an unknown id changes nothing', () {
      final notifier = CrmNotesNotifier([_note('a'), _note('b')]);
      notifier.togglePin('missing');
      expect([for (final n in notifier.state) n.id], ['a', 'b']);
      expect(notifier.state.every((n) => !n.pinned), isTrue);
    });
  });

  test('withPinned carries every other field, replies included', () {
    final original = NoteEntry(
      id: 'n1',
      author: 'Priya Saxena',
      time: '6 Aug',
      body: 'keep me',
      via: 'Call',
      replies: [const NoteReply(author: 'A', time: '1h', body: 'r')],
    );
    final pinned = original.withPinned(true);

    expect(pinned.pinned, isTrue);
    expect(pinned.id, 'n1');
    expect(pinned.author, 'Priya Saxena');
    expect(pinned.time, '6 Aug');
    expect(pinned.body, 'keep me');
    expect(pinned.via, 'Call');
    // The live list is carried over, not dropped — losing it would blank a
    // thread the moment someone pinned its parent.
    expect(pinned.replies.length, 1);
  });
}
