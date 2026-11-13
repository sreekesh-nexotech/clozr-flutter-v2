// The list headers' status groups (Oct 2026 redesign): which group a status
// falls in, what a group selection lists, and how the `status-counts`
// endpoints are read.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/status_groups/status_groups.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/application/providers/crm_catalog_providers.dart';
import 'package:clozrapp/features/crm/application/providers/crm_tasks_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_task.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/status_counts_remote_ds.dart';

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
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
    ..httpClientAdapter = a;
  return ApiService(tokens: TokenStorage(), dio: dio);
}

const _lanes = [
  CatalogOption(id: 's1', name: 'Open', statusType: 'open'),
  CatalogOption(id: 's2', name: 'Waiting on client', statusType: 'in_progress'),
  CatalogOption(id: 's3', name: 'In Progress', statusType: 'in_progress'),
  CatalogOption(id: 's4', name: 'Completed', statusType: 'completed'),
];

CrmTask _task(String id, String lane) => CrmTask(
      id: id,
      title: 'Task $id',
      type: 'call',
      leadId: '',
      status: 'todo',
      statusName: lane,
      priority: 'medium',
      assignee: 'me',
      due: '',
      dueNote: '',
    );

void main() {
  group('a status\'s group', () {
    test('leads and CRM tasks group by their status type', () {
      expect(
          StatusGroups.ofTyped(const CatalogOption(
              id: 'a', name: 'Proposal', statusType: 'in_progress')),
          'in_progress');
      expect(
          StatusGroups.ofTyped(const CatalogOption(id: 'a', name: 'Proposal')),
          isNull);
    });

    test(
        'projects, project tasks and tickets group by their flags, like the backend',
        () {
      expect(
          StatusGroups.ofProject(
              const CatalogOption(id: 'a', name: 'Delivered', isClosed: true)),
          'closed');
      expect(
          StatusGroups.ofProject(
              const CatalogOption(id: 'a', name: 'Planning')),
          'open');
      expect(
          StatusGroups.ofProjectTask(const CatalogOption(
              id: 'a', name: 'Dropped', isClosed: true, isCancelled: true)),
          'cancelled');
      expect(
          StatusGroups.ofProjectTask(
              const CatalogOption(id: 'a', name: 'Done', isClosed: true)),
          'completed');
      expect(
          StatusGroups.ofTicket(const CatalogOption(
              id: 'a', name: 'Fixed', isClosed: true, isOnHold: true)),
          'resolved');
      expect(
          StatusGroups.ofTicket(
              const CatalogOption(id: 'a', name: 'Parts due', isOnHold: true)),
          'on_hold');
      expect(StatusGroups.ofTicket(const CatalogOption(id: 'a', name: 'New')),
          'open');
    });
  });

  group('a header selection', () {
    Set<String> effective(Set<String> picked, String? group) =>
        StatusGroups.effectiveKeys(
          picked: picked,
          group: group,
          statuses: _lanes,
          groupOf: StatusGroups.ofTyped,
          keyOf: (s) => s.id,
        );

    test('a group on its own stands for every status in it', () {
      expect(effective(const {}, 'in_progress'), {'s2', 's3'});
      expect(effective(const {}, 'cancelled'), isEmpty);
    });

    test('a picked status narrows its group, and nothing picked is All', () {
      expect(effective(const {'s3'}, 'in_progress'), {'s3'});
      expect(effective(const {}, null), isEmpty);
    });

    test('the open group follows a status set from another screen', () {
      String? shown(Set<String> picked, String? group) =>
          StatusGroups.displayedGroup(
            picked: picked,
            group: group,
            statuses: _lanes,
            groupOf: StatusGroups.ofTyped,
            keyOf: (s) => s.id,
          );
      expect(shown(const {'s4'}, 'open'), 'completed');
      expect(shown(const {}, 'open'), 'open');
      // A folded key names no status, so the group set beside it stays open.
      expect(shown(const {'resolved'}, 'resolved'), 'resolved');
    });
  });

  group('GET /crm/…/status-counts/', () {
    test('reads the total, Other, each group and each status by name',
        () async {
      final adapter = _Adapter({
        'total': 435,
        'no_status': 13,
        'other': 13,
        'groups': [
          {'code': 'new', 'name': 'New', 'position': 0, 'count': 272},
          {
            'code': 'in_progress',
            'name': 'In progress',
            'position': 1,
            'count': 26
          },
        ],
        'statuses': [
          {
            'lead_status_id': 'x',
            'name': 'Contacted',
            'status_type': 'in_progress',
            'count': 26
          },
        ],
      });
      final out = await StatusCountsRemoteDataSource(_api(adapter))
          .fetch('/crm/leads/status-counts/', {
        'status__in': 'a,b',
        'status_type': 'won',
        'page': 2,
        'view_type': 'mobile',
        'search': 'acme',
        'is_archive': true,
      });

      expect(out['all'], 435);
      expect(out[StatusCountsRemoteDataSource.otherKey], 13);
      expect(out[StatusGroups.countKey('new')], 272);
      expect(out[StatusGroups.countKey('in_progress')], 26);
      expect(out['contacted'], 26);
      // The status facets and paging stay off the aggregate; the scope rides.
      final q = adapter.requests.single.queryParameters;
      expect(q.keys, unorderedEquals(['search', 'is_archive']));
    });

    test('a failed call answers empty, so the header counts the loaded rows',
        () async {
      final out = await StatusCountsRemoteDataSource(_api(_Adapter('not json')))
          .fetch('/crm/tasks/status-counts/', {});
      expect(out, isEmpty);
    });
  });

  group('the Tasks list', () {
    Future<List<CrmTask>> visible(
        {Set<String> chips = const {}, String? group}) async {
      final c = ProviderContainer(overrides: [
        crmTasksProvider.overrideWith((ref) async => [
              _task('1', 'Open'),
              _task('2', 'Waiting on client'),
              _task('3', 'In Progress'),
              _task('4', 'Completed'),
            ]),
        taskStatusOptionsProvider.overrideWithValue(_lanes),
        // No catalog fetches: the drawer codec would otherwise ask the server.
        crmCatalogRemoteDataSourceProvider.overrideWithValue(null),
      ]);
      addTearDown(c.dispose);
      await c.read(crmTasksProvider.future);
      c.read(crmTaskChipsProvider.notifier).state = chips;
      c.read(crmTaskGroupProvider.notifier).state = group;
      return c.read(visibleCrmTasksProvider);
    }

    test('a group lists every lane of its type', () async {
      expect([for (final t in await visible(group: 'in_progress')) t.id],
          ['2', '3']);
    });

    test('a lane picked inside the group narrows it', () async {
      expect([
        for (final t
            in await visible(group: 'in_progress', chips: {'In Progress'}))
          t.id
      ], [
        '3'
      ]);
    });

    test('a group the org has no lane in lists nothing', () async {
      expect(await visible(group: 'cancelled'), isEmpty);
    });

    test('no group and no lane is All', () async {
      expect(await visible(), hasLength(4));
    });
  });
}
