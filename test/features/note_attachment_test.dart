// Note attachments used to be fabricated in the widget ("Photo 1.jpg", 1.2 MB)
// and never uploaded. These cover the two halves of the fix: a picked file
// carries a real path, and it is POSTed as multipart to /crm/attachments/
// against the created note's id.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/models/note.dart';
import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/notes/infrastructure/data_sources/remote/notes_remote_ds.dart';

/// Captures the multipart request and answers with a hosted file.
class _UploadAdapter implements HttpClientAdapter {
  _UploadAdapter({this.body});

  final List<RequestOptions> requests = [];
  final Object? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body ??
          {
            'attachment_id': 'att-1',
            'name': 'survey.pdf',
            'file': 'https://cdn.example/survey.pdf',
          }),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

NotesRemoteDataSource _dsWith(_UploadAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
    ..httpClientAdapter = adapter;
  return NotesRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));
}

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('note_att');
    file = File('${tmp.path}/survey.pdf')..writeAsStringSync('%PDF-1.4 fake');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('NoteAttachment', () {
    test('a picked file is pending; an API one is not', () {
      final picked = NoteAttachment(
          name: 'survey.pdf', kind: 'file', localPath: file.path);
      const fromApi = NoteAttachment(
          name: 'survey.pdf', kind: 'file', url: 'https://cdn/survey.pdf');

      expect(picked.isPending, isTrue, reason: 'has a path, no url yet');
      expect(fromApi.isPending, isFalse);
    });

    test('copyWith swaps in the hosted url', () {
      final picked = NoteAttachment(
          name: 'survey.pdf', kind: 'file', localPath: file.path);

      final done = picked.copyWith(url: 'https://cdn/survey.pdf');

      expect(done.url, 'https://cdn/survey.pdf');
      expect(done.isPending, isFalse);
      expect(done.name, 'survey.pdf', reason: 'metadata survives');
    });
  });

  group('addAttachment', () {
    test('POSTs multipart to the attachments endpoint, linked to the note', () async {
      final adapter = _UploadAdapter();

      final result = await _dsWith(adapter).addAttachment(
        'note-42',
        NoteAttachment(name: 'survey.pdf', kind: 'file', localPath: file.path),
      );

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/crm/attachments/');
      expect(req.data, isA<FormData>());

      // The link back at the note is what makes the upload land on it.
      final fields = Map.fromEntries((req.data as FormData).fields);
      expect(fields['related_to'], 'note');
      expect(fields['related_to_id'], 'note-42');
      expect(fields['name'], 'survey.pdf');
      expect((req.data as FormData).files.single.key, 'file_upload');

      expect(result!.url, 'https://cdn.example/survey.pdf');
      expect(result.isPending, isFalse);
    });

    test('an attachment with no local file is not uploaded at all', () async {
      final adapter = _UploadAdapter();

      final result = await _dsWith(adapter).addAttachment(
        'note-42',
        const NoteAttachment(name: 'already.pdf', kind: 'file'),
      );

      expect(adapter.requests, isEmpty, reason: 'nothing to send');
      expect(result, isNull);
    });

    test('a response without a file url yields null rather than a bad link', () async {
      final adapter = _UploadAdapter(body: {'attachment_id': 'att-1'});

      final result = await _dsWith(adapter).addAttachment(
        'note-42',
        NoteAttachment(name: 'survey.pdf', kind: 'file', localPath: file.path),
      );

      expect(result, isNull);
    });
  });
}
