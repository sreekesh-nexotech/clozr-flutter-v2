import 'package:clozrapp/features/crm/domain/entities/lead_file.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/attachments_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

/// UI/UX audit #02: an Ops-task file row shows type, size and uploader.
void main() {
  group('LeadFile.sizeLabel', () {
    LeadFile f(int? b) => LeadFile(
        id: 'a', name: 'x.txt', url: '', uploadedBy: '', uploadedAt: '',
        sizeBytes: b);
    test('bytes / KB / MB', () {
      expect(f(4).sizeLabel, '4 B');
      expect(f(1536).sizeLabel, '1.5 KB');
      expect(f(204800).sizeLabel, '200 KB');
      expect(f(3 * 1024 * 1024).sizeLabel, '3.0 MB');
    });
    test('unknown size → empty', () => expect(f(null).sizeLabel, ''));
  });

  test('fileFromJson reads size_bytes and uploaded_by.full_name', () {
    final file = AttachmentsRemoteDataSource.fileFromJson({
      'attachment_id': 'att-1',
      'name': 'qatf.txt',
      'file_url': 'https://cdn/x/qatf.txt?token=t',
      'size_bytes': 4,
      'uploaded_by': {
        'user_id': 'u-1',
        'full_name': 'Sufail Salim',
        'first_name': 'Sufail',
        'last_name': 'Salim',
      },
      'uploaded_at': '2026-11-11T12:58:41+05:30',
    })!;
    expect(file.ext, 'TXT');
    expect(file.sizeLabel, '4 B');
    expect(file.uploaderName, 'Sufail Salim');
  });

  test('fileFromJson without size or uploader object', () {
    final file = AttachmentsRemoteDataSource.fileFromJson({
      'attachment_id': 'att-2',
      'name': 'a.pdf',
      'uploaded_by': 'u-2',
    })!;
    expect(file.sizeBytes, isNull);
    expect(file.uploaderName, '');
  });
}
