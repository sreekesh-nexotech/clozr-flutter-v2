import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/domain/entities/lead_file.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/attachments_remote_ds.dart';

void main() {
  const meUuid = '11111111-1111-4111-8111-111111111111';
  const otherUuid = '22222222-2222-4222-8222-222222222222';
  const leadId = 'lead-uuid-1';

  final now = DateTime(2026, 8, 6, 14, 0);

  setUp(() {
    UserDirectory.currentUserId = meUuid;
  });

  tearDown(UserDirectory.reset);

  Map<String, dynamic> row({
    String id = 'att-uuid-1',
    Object? name = 'Contract.pdf',
    String file = 'https://cdn.example.com/files/Contract.pdf',
    String uploader = meUuid,
    Object? uploadedAt,
  }) =>
      {
        'attachment_id': id,
        'name': name,
        'file': file,
        'description': 'Signed contract',
        'uploaded_at':
            uploadedAt ?? DateTime(2026, 8, 4, 10).toIso8601String(),
        'uploaded_by': {'user_id': uploader, 'full_name': 'Manoj Varma'},
        'related_to_model': 'lead',
        'related_to_object_id': leadId,
      };

  group('fileFromJson', () {
    test('maps a full row', () {
      final f = AttachmentsRemoteDataSource.fileFromJson(row(), now: now)!;

      expect(f.id, 'att-uuid-1');
      expect(f.name, 'Contract.pdf');
      expect(f.url, 'https://cdn.example.com/files/Contract.pdf');
      expect(f.description, 'Signed contract');
      expect(f.uploadedAt, '2d ago');
    });

    test('the signed-in user maps to the "me" sentinel', () {
      final mine = AttachmentsRemoteDataSource.fileFromJson(row(), now: now)!;
      final theirs = AttachmentsRemoteDataSource.fileFromJson(
          row(uploader: otherUuid),
          now: now)!;

      expect(mine.uploadedBy, 'me');
      expect(theirs.uploadedBy, otherUuid);
    });

    test('a blank name falls back to the file name in the URL', () {
      final f = AttachmentsRemoteDataSource.fileFromJson(
          row(name: null, file: 'https://cdn.example.com/x/Floor%20plan.pdf'),
          now: now)!;

      expect(f.name, 'Floor plan.pdf');
    });

    test('a query string on the URL does not leak into the name', () {
      final f = AttachmentsRemoteDataSource.fileFromJson(
          row(name: null, file: 'https://cdn.example.com/a/Deck.pdf?sig=abc123'),
          now: now)!;

      expect(f.name, 'Deck.pdf');
    });

    test('a row with neither name nor URL still renders', () {
      final f = AttachmentsRemoteDataSource.fileFromJson(
          {'attachment_id': 'x'},
          now: now)!;

      expect(f.name, 'Attachment');
      expect(f.url, '');
      expect(f.description, '');
    });

    test('a row without an id is skipped rather than fatal', () {
      expect(
        AttachmentsRemoteDataSource.fileFromJson({'name': 'orphan.pdf'}),
        isNull,
      );
    });
  });

  group('LeadFile.ext', () {
    test('reads the extension from the name', () {
      const f = LeadFile(id: '1', name: 'Contract.pdf', url: '', uploadedBy: 'me', uploadedAt: '');
      expect(f.ext, 'PDF');
    });

    test('falls back to the URL when the name has none', () {
      const f = LeadFile(id: '1', name: 'Contract', url: 'https://cdn/x/c.docx', uploadedBy: 'me', uploadedAt: '');
      expect(f.ext, 'DOCX');
    });

    test('an extensionless file reads as FILE, not as a URL fragment', () {
      const f = LeadFile(id: '1', name: 'README', url: 'https://cdn.example.com/files', uploadedBy: 'me', uploadedAt: '');
      expect(f.ext, 'FILE');
    });
  });

  group('mapRows', () {
    test('sorts newest-first', () {
      final rows = [
        row(id: 'old', uploadedAt: DateTime(2026, 7, 1).toIso8601String()),
        row(id: 'new', uploadedAt: DateTime(2026, 8, 5).toIso8601String()),
        row(id: 'mid', uploadedAt: DateTime(2026, 8, 1).toIso8601String()),
      ];

      final mapped = AttachmentsRemoteDataSource.mapRows(rows);

      expect(mapped.map((f) => f.id), ['new', 'mid', 'old']);
    });

    test('undated rows sink to the bottom instead of disappearing', () {
      final mapped = AttachmentsRemoteDataSource.mapRows([
        {'attachment_id': 'undated', 'name': 'a.pdf'},
        row(id: 'dated'),
      ]);

      expect(mapped.map((f) => f.id), ['dated', 'undated']);
    });

    test('malformed rows are dropped, the rest still map', () {
      final mapped = AttachmentsRemoteDataSource.mapRows([
        row(id: 'good'),
        {'no_id': true},
      ]);

      expect(mapped.map((f) => f.id), ['good']);
    });
  });
}
