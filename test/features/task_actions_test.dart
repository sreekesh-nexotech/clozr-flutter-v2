// The task detail screen's actions — edit, duplicate, delete, file upload —
// were all toasts. These pin the requests that replaced them, and the write-key
// rule the edit form depends on.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/attachments_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/crm_tasks_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

/// Records every request and answers with a task row.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.body});

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
      jsonEncode(body ?? const {'task_id': 'T1', 'title': 'Prepare BOQ'}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiService _api(_Adapter a) {
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))..httpClientAdapter = a;
  return ApiService(tokens: TokenStorage(), dio: dio);
}

ViewColumn _col(String name, String type, {String related = ''}) => ViewColumn(
      name: name,
      label: name,
      order: 1,
      type: type,
      relatedModel: related,
      inFields: true,
    );

void main() {
  group('edit', () {
    test('PATCHes the task with the fields it was given', () async {
      final a = _Adapter();
      await CrmTasksRemoteDataSource(_api(a))
          .updateTask('T1', {'description': 'probe', 'duration': 45});

      final req = a.requests.single;
      expect(req.method, 'PATCH');
      expect(req.path, '/crm/tasks/T1/');
      expect(req.data, {'description': 'probe', 'duration': 45});
    });

    test('status writes to status_id; every other field writes by its own name', () {
      // Verified live: `status` is read-only on the serializer, so a write to it
      // returns 200 and stores nothing. `priority`, `assigned_to`,
      // `assigned_team` and `assignees` all store under their plain names.
      expect(LeadsRemoteDataSource.writeKeyFor(_col('status', 'foreignkey')), 'status_id');
      expect(LeadsRemoteDataSource.writeKeyFor(_col('priority', 'foreignkey')), 'priority');
      expect(LeadsRemoteDataSource.writeKeyFor(_col('assigned_to', 'foreignkey')), 'assigned_to');
      expect(LeadsRemoteDataSource.writeKeyFor(_col('assignees', 'manytomany')), 'assignees');
      expect(LeadsRemoteDataSource.writeKeyFor(_col('duration', 'integer')), 'duration');
    });
  });

  group('delete', () {
    test('DELETEs the record', () async {
      final a = _Adapter();
      await CrmTasksRemoteDataSource(_api(a)).deleteTask('T1');

      expect(a.requests.single.method, 'DELETE');
      expect(a.requests.single.path, '/crm/tasks/T1/');
    });
  });

  group('duplicate', () {
    test('re-posts as a new task, carrying the record link', () async {
      final a = _Adapter();
      await CrmTasksRemoteDataSource(_api(a)).createTask({
        'title': 'Prepare BOQ (copy)',
        'task_type': 'Task',
        'description': 'from sheet',
        'due_date': '2026-08-20',
        'related_to': 'lead',
        'related_to_id': 'L9',
      });

      final req = a.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/crm/tasks/');
      final sent = req.data as Map;
      expect(sent['title'], 'Prepare BOQ (copy)');
      expect(sent['is_followup'], false);
      // The copy stays beside the original.
      expect(sent['related_to'], 'lead');
      expect(sent['related_to_id'], 'L9');
    });

    test('a half-populated link is dropped rather than sent and rejected', () {
      expect(CrmTasksRemoteDataSource.relatedTo(const {'related_to': 'lead'}), isEmpty);
      expect(CrmTasksRemoteDataSource.relatedTo(const {'related_to_id': 'L9'}), isEmpty);
    });
  });

  group('file upload', () {
    late Directory tmp;
    late File file;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('task_att');
      file = File('${tmp.path}/boq.pdf')..writeAsStringSync('%PDF fake');
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('posts multipart against the task, not a lead', () async {
      final a = _Adapter(body: const {
        'attachment_id': 'a1',
        'name': 'boq.pdf',
        'file': 'https://cdn/boq.pdf',
      });

      await AttachmentsRemoteDataSource(_api(a)).uploadFile(
        relatedTo: 'task',
        relatedToId: 'T1',
        path: file.path,
        name: 'boq.pdf',
      );

      final req = a.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/crm/attachments/');
      final fields = Map.fromEntries((req.data as FormData).fields);
      expect(fields['related_to'], 'task');
      expect(fields['related_to_id'], 'T1');
      expect((req.data as FormData).files.single.key, 'file_upload');
    });

    test('reads a task’s files with the same polymorphic scope', () async {
      final a = _Adapter(body: const {'count': 0, 'results': []});

      await AttachmentsRemoteDataSource(_api(a)).fetchFileRows('task', 'T1');

      final q = a.requests.single.queryParameters;
      expect(q['related_to'], 'task');
      expect(q['related_to_id'], 'T1');
    });
  });

  group('detail schema', () {
    test('asks for the detail view type', () async {
      final a = _Adapter(body: const {
        'has_org_config': true,
        'all_fields': {
          'columns': [
            {
              'name': 'title',
              'label': 'Task',
              'order': 1,
              'visible': true,
              'field_info': {'type': 'string'},
            },
          ],
        },
      });

      final schema = await CrmTasksRemoteDataSource(_api(a)).fetchTaskDetailSchema();

      expect(a.requests.single.path, '/crm/tasks/schema/');
      expect(a.requests.single.queryParameters['view_type'], 'detail');
      expect(schema.shows('title'), isTrue);
    });

    test('a failed schema fetch degrades to the empty layout', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
        ..httpClientAdapter = _ThrowingAdapter();
      final ds = CrmTasksRemoteDataSource(
          ApiService(tokens: TokenStorage(), dio: dio));

      expect((await ds.fetchTaskDetailSchema()).isEmpty, isTrue);
    });
  });
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      throw DioException(requestOptions: options, message: 'offline');

  @override
  void close({bool force = false}) {}
}
