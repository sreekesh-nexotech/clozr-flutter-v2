// The Add follow-up sheet is built from the org's `detail` layout, and what it
// submits has to be the shape the API stores.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/followup_schema_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/followups_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);

  final Object body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), 201, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiService _api(_Adapter a) {
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))..httpClientAdapter = a;
  return ApiService(tokens: TokenStorage(), dio: dio);
}

/// The Acme org's real follow-up `detail` layout.
Map<String, dynamic> _detailSchema() => {
      'model': 'Followup',
      'view_type': 'detail',
      'has_org_config': true,
      'all_fields': {
        'columns': [
          {'name': 'title', 'label': 'Task', 'order': 1, 'visible': true,
           'field_info': {'type': 'string'}},
          {'name': 'task_type', 'label': 'Type', 'order': 2, 'visible': true,
           'field_info': {'type': 'string'}},
          {'name': 'status', 'label': 'Status', 'order': 3, 'visible': true,
           'field_info': {'type': 'foreignkey', 'related_model': 'CRMTaskStatus'}},
          {'name': 'priority', 'label': 'Priority', 'order': 4, 'visible': true,
           'field_info': {'type': 'foreignkey', 'related_model': 'TaskPriority'}},
          {'name': 'due_date', 'label': 'Due Date', 'order': 5, 'visible': true,
           'field_info': {'type': 'date'}},
          // Display-only: the API accepts a write and stores nothing.
          {'name': 'related_to', 'label': 'Related To', 'order': 9, 'visible': true},
        ],
      },
    };

void main() {
  group('the form layout', () {
    test('comes from the detail view type, scoped to follow-ups', () async {
      final adapter = _Adapter(_detailSchema());
      await FollowupSchemaRemoteDataSource(_api(adapter)).fetchDetailSchema();

      final q = adapter.requests.single.queryParameters;
      expect(q['view_type'], 'detail');
      // Without this the schema describes the Tasks screen instead.
      expect(q['is_followup'], true);
    });

    test('only editable columns become inputs', () {
      final schema = ViewSchema.fromResponse(_detailSchema());
      expect(schema.columns.map((c) => c.name), contains('related_to'));
      // `related_to` is visible but display-only — a box for it would accept
      // input the API discards.
      expect(schema.editableColumns.map((c) => c.name).toList(),
          ['title', 'task_type', 'status', 'priority', 'due_date']);
    });

    test('status is written as status_id, everything else as named', () {
      final schema = ViewSchema.fromResponse(_detailSchema());
      String keyOf(String name) =>
          LeadsRemoteDataSource.writeKeyFor(schema.column(name)!);
      // Verified live: a write to `status` returns 200 and changes nothing.
      expect(keyOf('status'), 'status_id');
      expect(keyOf('priority'), 'priority');
      expect(keyOf('title'), 'title');
    });
  });

  group('the create request', () {
    test('sends the schema payload as given, and forces is_followup', () async {
      final adapter = _Adapter({'task_id': 't1', 'title': 'Ring back'});
      await FollowupsRemoteDataSource(_api(adapter)).createFollowupFields({
        'title': 'Ring back',
        'task_type': 'WhatsApp',
        'status_id': 'st-open',
        'priority': 'pr-high',
        'due_date': '2026-09-01',
      });

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/crm/tasks/');
      expect(req.data, {
        'title': 'Ring back',
        // Not one of the Task model's own choices, but the API stores it and
        // it is what the org's follow-up type catalog offers.
        'task_type': 'WhatsApp',
        'status_id': 'st-open',
        'priority': 'pr-high',
        'due_date': '2026-09-01',
        // Without this the row lands on the Tasks list instead.
        'is_followup': true,
      });
    });

    test('empty strings are dropped, nulls are kept', () async {
      final adapter = _Adapter({'task_id': 't1', 'title': 'X'});
      await FollowupsRemoteDataSource(_api(adapter)).createFollowupFields({
        'title': 'X',
        'description': '   ',
        'due_date': null,
      });

      final data = adapter.requests.single.data as Map;
      // The API rejects "" for typed fields; null is the form's "clear".
      expect(data.containsKey('description'), isFalse);
      expect(data.containsKey('due_date'), isTrue);
      expect(data['due_date'], isNull);
    });

    test('carries the lead link when opened from one', () async {
      final adapter = _Adapter({'task_id': 't1', 'title': 'X'});
      await FollowupsRemoteDataSource(_api(adapter)).createFollowupFields({
        'title': 'X',
        'related_to': 'lead',
        'related_to_id': 'lead-1',
      });
      final data = adapter.requests.single.data as Map;
      expect(data['related_to'], 'lead');
      expect(data['related_to_id'], 'lead-1');
    });
  });
}
