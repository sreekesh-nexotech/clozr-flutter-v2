// The project Files tab could read files but never add one, so a drawing could
// only arrive from another client. `operations.md` §15 gives the upload as
// multipart `{project, file_upload}` — the serializer also requires `name`,
// which these pin along with the rest of the request.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/operations/infrastructure/data_sources/remote/projects_remote_ds.dart';

/// Captures the request it was handed and answers 201.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? last;
  FormData? form;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    if (options.data is FormData) form = options.data as FormData;
    return ResponseBody.fromString(jsonEncode({'attachment_id': 'a-1'}), 201,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _CapturingAdapter adapter;
  late ProjectsRemoteDataSource ds;
  late File file;

  setUp(() async {
    adapter = _CapturingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
      ..httpClientAdapter = adapter;
    ds = ProjectsRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));
    file = File('${Directory.systemTemp.path}/site-drawing.pdf')
      ..writeAsStringSync('%PDF-1.4 probe');
  });

  tearDown(() {
    if (file.existsSync()) file.deleteSync();
  });

  test('posts multipart to the project-attachments collection', () async {
    await ds.uploadProjectAttachment(
        projectId: 'p-1', path: file.path, name: 'site-drawing.pdf');

    expect(adapter.last?.method, 'POST');
    expect(adapter.last?.path, '/projects/project-attachments/');
    expect(adapter.form, isNotNull, reason: 'must be multipart, not JSON');
  });

  test('carries the project, the name and the file', () async {
    await ds.uploadProjectAttachment(
        projectId: 'p-1', path: file.path, name: 'site-drawing.pdf');

    final fields = {for (final f in adapter.form!.fields) f.key: f.value};
    expect(fields['project'], 'p-1');
    // Undocumented but required: without it the API answers
    // `400 {"name": ["This field is required."]}`.
    expect(fields['name'], 'site-drawing.pdf');
    expect(adapter.form!.files.single.key, 'file_upload');
  });

  test('the uploaded file keeps its own filename', () async {
    await ds.uploadProjectAttachment(
        projectId: 'p-1', path: file.path, name: 'site-drawing.pdf');

    expect(adapter.form!.files.single.value.filename, 'site-drawing.pdf');
  });
}
