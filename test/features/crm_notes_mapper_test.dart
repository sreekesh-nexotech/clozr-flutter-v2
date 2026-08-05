import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/notes/infrastructure/data_sources/remote/notes_remote_ds.dart';

void main() {
  final now = DateTime(2026, 7, 1, 10, 0);

  tearDown(UserDirectory.reset);

  Map<String, dynamic> row() => {
        'note_id': 'n-uuid-1',
        'title': null,
        'content': 'Client wants the quote split into two phases.',
        'note_type': {
          'note_type_id': 'nt-1',
          'name': 'Call',
          'color': '#16a34a',
        },
        'reply_count': 1,
        'attachments': <Object>[],
        'created_by': {
          'user_id': 'u-priya',
          'full_name': 'Priya Nair',
        },
        'created_at': '2026-06-30T16:20:00Z',
      };

  group('NotesRemoteDataSource.noteFromJson', () {
    test('maps a full note row onto NoteEntry', () {
      final n = NotesRemoteDataSource.noteFromJson(row(), now: now)!;
      expect(n.id, 'n-uuid-1');
      expect(n.author, 'Priya Nair');
      expect(n.body, 'Client wants the quote split into two phases.');
      expect(n.via, 'Call');
      expect(n.time, isNotEmpty); // relativeTime of created_at
      expect(n.replies, isEmpty); // replies load lazily
      expect(n.attachments, isEmpty);
    });

    test('via only surfaces Call/Email tags', () {
      String? viaOf(Object? noteType) => NotesRemoteDataSource.noteFromJson(
            {...row(), 'note_type': noteType},
            now: now,
          )!
              .via;
      expect(viaOf({'name': 'Email'}), 'Email');
      expect(viaOf({'name': 'Internal'}), isNull);
      expect(viaOf(null), isNull);
      expect(viaOf('Call'), isNull); // non-map shape → no tag
    });

    test('maps attachments, inferring image kind from the file extension', () {
      final n = NotesRemoteDataSource.noteFromJson({
        ...row(),
        'attachments': [
          {
            'attachment_id': 'a-1',
            'name': 'site-photo.JPG',
            'file': 'https://cdn.example.com/site-photo.JPG',
          },
          {
            'attachment_id': 'a-2',
            'name': 'site-survey.pdf',
            'file': 'https://cdn.example.com/site-survey.pdf?token=abc',
          },
        ],
      }, now: now)!;
      expect(n.attachments, hasLength(2));
      expect(n.attachments[0].kind, 'image');
      expect(n.attachments[0].isImage, isTrue);
      expect(n.attachments[0].name, 'site-photo.JPG');
      expect(n.attachments[0].url, 'https://cdn.example.com/site-photo.JPG');
      expect(n.attachments[1].kind, 'file');
      expect(n.attachments[1].name, 'site-survey.pdf');
    });

    test('is defensive: no note_id → null; junk fields tolerated', () {
      expect(NotesRemoteDataSource.noteFromJson({'content': 'x'}), isNull);
      final junk = NotesRemoteDataSource.noteFromJson({
        'note_id': 'n-2',
        'content': null,
        'created_by': 'not-a-map',
        'note_type': 42,
        'attachments': 'not-a-list',
        'created_at': 'garbage',
      }, now: now)!;
      expect(junk.author, 'Unknown');
      expect(junk.body, '');
      expect(junk.via, isNull);
      expect(junk.attachments, isEmpty);
      expect(junk.time, '');
    });
  });

  group('NotesRemoteDataSource.replyFromJson', () {
    test('maps a created reply with a "Just now" timestamp', () {
      final r = NotesRemoteDataSource.replyFromJson({
        'note_id': 'n-uuid-2',
        'content': 'Keep phase 1 under 25L.',
        'parent_note': 'n-uuid-1',
        'created_by': {'user_id': 'u-priya', 'full_name': 'Priya Nair'},
      });
      expect(r.author, 'Priya Nair');
      expect(r.time, 'Just now');
      expect(r.body, 'Keep phase 1 under 25L.');
    });

    test('falls back to the posted body and "You" on shape surprises', () {
      final r = NotesRemoteDataSource.replyFromJson(
        const {},
        fallbackBody: 'Typed reply',
      );
      expect(r.author, 'You');
      expect(r.body, 'Typed reply');
    });
  });
}
