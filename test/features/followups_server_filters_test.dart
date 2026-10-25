// Follow-ups: the drawer as the webapp's task drawer (a server query whose
// params a saved view shares with Tasks), the card as the org's mobile layout,
// and the row mapper.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/application/filters/followups_filter_spec.dart';
import 'package:clozrapp/features/crm/application/filters/tasks_filter_spec.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/followup_schema_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/followups_remote_ds.dart';

/// The Acme org's real task statuses.
final _statuses = [
  const CatalogOption(id: 'st-open', name: 'Open', statusType: 'open'),
  const CatalogOption(id: 'st-prog', name: 'In Progress', statusType: 'in_progress'),
  const CatalogOption(id: 'st-done', name: 'Completed', statusType: 'completed'),
  const CatalogOption(id: 'st-canc', name: 'Cancelled', statusType: 'cancelled'),
];

const _priorities = [
  CatalogOption(id: 'pr-high', name: 'high'),
  CatalogOption(id: 'pr-low', name: 'low'),
];

TaskFilterCodec _codec() => TaskFilterCodec(statuses: _statuses, priorities: _priorities);

const _types = [
  CatalogOption(id: 'uuid-call', name: 'Call'),
  CatalogOption(id: 'uuid-site', name: 'Site Visit'),
];

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
  group('drawer → /crm/tasks/ params (webapp task drawer)', () {
    test('offers the webapp facets, with the org follow-up types by name', () {
      final spec = buildFollowupsFilterSpec(typeCatalog: _types, statusCatalog: _statuses, priorityCatalog: _priorities);
      final fields = {for (final f in spec.sections.expand((s) => s.fields)) f.id: f};
      expect(fields.keys, containsAll(['assignees', 'statuses', 'types', 'priorities', 'due']));
      expect(fields['types']!.options.map((o) => o.id), ['Call', 'Site Visit']);
      expect(spec.title, 'Filter follow-ups by:');
    });

    test('falls back to the built-in follow-up types before the catalog loads', () {
      final spec = buildFollowupsFilterSpec();
      final types = spec.sections.expand((s) => s.fields).firstWhere((f) => f.id == 'types');
      expect(types.options.map((o) => o.id), kBuiltinFollowupTypes);
    });

    test('type sends names; status is sends NAMES, is-not sends ids', () {
      expect(_codec().encode(_values({'types': ChoiceValue(ids: {'Call'})})), {'task_type__in': 'Call'});
      expect(_codec().encode(_values({'statuses': ChoiceValue(ids: {'st-done'})})), {'status__in': 'Completed'});
      expect(_codec().encode(_values({'statuses': ChoiceValue(ids: {'st-done'}, isNot: true)})), {'status__not': 'st-done'});
    });

    test('Overdue is is_overdue; a range is due_date_after/before', () {
      expect(_codec().encode(_values({'due': const DateValue(chip: 'overdue')})), {'is_overdue': 'true'});
      expect(
        _codec().encode(_values({'due': DateValue(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31))})),
        {'due_date_after': '2026-10-01', 'due_date_before': '2026-10-31'},
      );
    });

    test('a saved view decodes back into the same drawer (shared with Tasks)', () {
      final spec = buildFollowupsFilterSpec(typeCatalog: _types, statusCatalog: _statuses, priorityCatalog: _priorities);
      final def = _codec().encode(_values({
        'types': ChoiceValue(ids: {'Call'}),
        'statuses': ChoiceValue(ids: {'st-open'}, isNot: true),
      }));
      final back = _codec().decode(def, spec);
      expect(back.choice('types')!.ids, {'Call'});
      expect(back.choice('statuses')!.ids, {'st-open'});
      expect(back.choice('statuses')!.isNot, isTrue);
    });

    test('an untouched drawer encodes to nothing', () {
      expect(_codec().encode(FilterValues()), isEmpty);
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

    test('due caption: overdue / Today / In 2-3d, none once completed or cancelled', () {
      final now = DateTime(2026, 10, 24);
      String note(String due, {String status = 'Open', Map<String, String> types = const {}}) =>
          FollowupsRemoteDataSource.followupFromJson(
            {'task_id': 'x', 'title': 'X', 'status': status, 'due_date': due},
            now: now,
            statusTypes: types,
          )!.dueNote;
      expect(note('2026-10-22'), '2d overdue');
      expect(note('2026-10-24'), 'Today');
      expect(note('2026-10-26'), 'In 2d');
      expect(note('2026-10-30'), '');
      expect(note('2026-10-22', status: 'Completed', types: const {'completed': 'completed'}), '');
      expect(note('2026-10-22', status: 'Cancelled', types: const {'cancelled': 'cancelled'}), '');
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
