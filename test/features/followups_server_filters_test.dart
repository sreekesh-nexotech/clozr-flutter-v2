// Follow-ups: the drawer as a server query, the status tabs as the org's own
// task statuses, and the card as the org's mobile layout.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/application/filters/followup_filter_codec.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/followup_schema_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/followups_remote_ds.dart';

const _meUuid = '11111111-1111-4111-8111-111111111111';

/// The Acme org's real task statuses.
final _statuses = [
  const CatalogOption(id: 'st-open', name: 'Open', statusType: 'open'),
  const CatalogOption(id: 'st-prog', name: 'In Progress', statusType: 'in_progress'),
  const CatalogOption(id: 'st-done', name: 'Completed', statusType: 'completed'),
  const CatalogOption(id: 'st-canc', name: 'Cancelled', statusType: 'cancelled'),
];

FollowupFilterCodec _codec() =>
    FollowupFilterCodec(statuses: _statuses, currentUserId: _meUuid);

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
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
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

FilterValues _values(Map<String, FilterValue> m) => FilterValues(m);

void main() {
  group('drawer → /crm/tasks/ params', () {
    test('type is / is not both send names', () {
      expect(
        _codec().encode(_values({'types': ChoiceValue(ids: {'Email', 'Call'})})),
        {'task_type__in': 'Email,Call'},
      );
      expect(
        _codec().encode(
            _values({'types': ChoiceValue(ids: {'Email'}, isNot: true)})),
        {'task_type__not': 'Email'},
      );
    });

    test('status is sends the NAME, is-not sends the ID', () {
      // Verified against a live org: `status__in` matches on the name and a
      // uuid finds nothing, while `status__not` wants the id and 500s on a
      // name. The two halves of one toggle are genuinely asymmetric.
      expect(
        _codec().encode(_values({'statuses': ChoiceValue(ids: {'completed'})})),
        {'status__in': 'completed'},
      );
      expect(
        _codec().encode(
            _values({'statuses': ChoiceValue(ids: {'completed'}, isNot: true)})),
        {'status__not': 'st-done'},
      );
    });

    test('a status the org no longer has is dropped from an is-not', () {
      // Sending the raw name there would be a 500, so it must not slip through.
      expect(
        _codec().encode(
            _values({'statuses': ChoiceValue(ids: {'gone'}, isNot: true)})),
        isEmpty,
      );
    });

    test("assignee resolves the 'me' sentinel to a real uuid", () {
      expect(
        _codec().encode(_values({'owners': ChoiceValue(ids: {'me'})})),
        {'assigned_to__in': _meUuid},
      );
    });

    test('a due-date chip becomes a concrete range', () {
      filterNow = () => DateTime(2026, 8, 6);
      addTearDown(() => filterNow = defaultFilterNow);
      expect(
        _codec().encode(_values({'due': const DateValue(chip: 'next7')})),
        {'due_date_after': '2026-08-06', 'due_date_before': '2026-08-13'},
      );
    });

    test('an untouched drawer encodes to nothing', () {
      expect(_codec().encode(FilterValues()), isEmpty);
    });

    test('the related-to section is not encoded — no param exists for it', () {
      expect(
        _codec().encode(_values({'companies': ChoiceValue(ids: {'Acme Ltd'})})),
        isEmpty,
      );
    });
  });

  group('the request', () {
    test('carries the filters, and paging keys survive a collision', () async {
      final adapter = _Adapter({'count': 0, 'next': null, 'results': []});
      final ds = FollowupsRemoteDataSource(_api(adapter));

      await ds.fetchFollowupRows(filters: const {
        'status__not': 'st-done',
        'task_type__in': 'Email',
        'page': 99,
      });

      final q = adapter.requests.single.queryParameters;
      expect(q['status__not'], 'st-done');
      expect(q['task_type__in'], 'Email');
      expect(q['is_followup'], 'true'); // the scope is never lost
      expect(q['page'], isNull, reason: 'a stored page must not steer the walk');
    });
  });

  group('the card layout', () {
    test('asks for the follow-up mobile schema, not the task one', () async {
      final adapter = _Adapter({
        'has_org_config': true,
        'all_fields': {
          'columns': [
            {'name': 'title', 'label': 'Task', 'order': 1, 'visible': true},
            {'name': 'status', 'label': 'Status', 'order': 2, 'visible': true},
            {'name': 'priority', 'label': 'Priority', 'order': 3, 'visible': true},
          ],
        },
      });

      final schema = await FollowupSchemaRemoteDataSource(_api(adapter)).fetchCardSchema();

      final q = adapter.requests.first.queryParameters;
      expect(q['view_type'], 'mobile');
      // Without this the response describes the Tasks screen instead.
      expect(q['is_followup'], true);
      expect(schema.columns.map((c) => c.name), ['title', 'status', 'priority']);
    });

    test('falls back to the list layout when mobile has no columns', () async {
      final adapter = _Adapter({
        'all_fields': {
          'columns': [
            {'name': 'title', 'label': 'Task', 'order': 1, 'visible': false},
          ],
        },
      });
      await FollowupSchemaRemoteDataSource(_api(adapter)).fetchCardSchema();
      expect(adapter.requests.map((r) => r.queryParameters['view_type']).toList(),
          ['mobile', 'list']);
    });

    test('an empty schema shows every slot — the built-in layout', () {
      expect(ViewSchema.empty.shows('priority'), isTrue);
      expect(ViewSchema.empty.shows('anything'), isTrue);
    });

    test('a configured schema hides what the org left out', () {
      const schema = ViewSchema(columns: [
        ViewColumn(name: 'title', label: 'Task', order: 1),
        ViewColumn(name: 'status', label: 'Status', order: 2),
      ]);
      expect(schema.shows('status'), isTrue);
      expect(schema.shows('task_type'), isFalse);
      expect(schema.shows('related_to'), isFalse);
    });
  });

  group('the row mapper', () {
    test('keeps the org status name and the priority beside the bucket', () {
      final fu = FollowupsRemoteDataSource.followupFromJson({
        'task_id': 't1',
        'title': 'Ring back',
        'task_type': 'Call',
        'status': {'name': 'Cancelled'},
        'priority': {'name': 'High'},
        'due_date': '2026-09-01',
      })!;
      // The three-way bucket cannot express Cancelled…
      expect(fu.status, anyOf('due', 'overdue', 'done'));
      // …so the org's own name is what the tabs and Status filter join on.
      expect(fu.statusName, 'Cancelled');
      expect(fu.statusKey, 'cancelled');
      expect(fu.priority, 'High');
    });

    test('a row with no status falls back to the derived bucket', () {
      final fu = FollowupsRemoteDataSource.followupFromJson({
        'task_id': 't2',
        'title': 'X',
      })!;
      expect(fu.statusName, isEmpty);
      expect(fu.statusKey, fu.status);
    });
  });
}
