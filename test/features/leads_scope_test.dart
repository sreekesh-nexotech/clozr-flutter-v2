// "My leads / All leads" is a server-side scope, not a client-side filter.
// These lock in the two halves of that: the request the data source builds
// (`?is_teams=true`, re-sent on every page), and the provider wiring that turns
// a toggle into a fetch for the scope being entered.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/application/providers/leads_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/lead.dart';
import 'package:clozrapp/features/crm/domain/repositories/leads_repository.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/local/leads_mock_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';
import 'package:clozrapp/features/crm/infrastructure/repositories/leads_repository_impl.dart';

/// Serves a fixed number of DRF pages and records every request it saw.
class _PagingAdapter implements HttpClientAdapter {
  _PagingAdapter({this.pages = 1});

  final int pages;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final page = int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
    final last = page >= pages;
    return ResponseBody.fromString(
      jsonEncode({
        'count': pages,
        'next': last ? null : 'https://x/api/v1/crm/leads/?page=${page + 1}',
        'previous': null,
        'results': [
          {'lead_id': 'L$page', 'lead_name': 'Lead $page'},
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiService _apiWith(_PagingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
    ..httpClientAdapter = adapter;
  return ApiService(tokens: TokenStorage(), dio: dio);
}

/// Records the scope each `getLeads` call was made with.
class _RecordingRepo implements LeadsRepository {
  final List<bool> calls = [];

  /// The server-side filter params each call carried.
  final List<Map<String, dynamic>> filterCalls = [];

  @override
  Future<List<Lead>> getLeads({
    bool mineOnly = false,
    Map<String, dynamic> filters = const {},
  }) async {
    calls.add(mineOnly);
    filterCalls.add(filters);
    return [
      Lead(
        id: mineOnly ? 'MINE' : 'ALL',
        name: 'x',
        initials: 'X',
        company: null,
        project: '',
        value: '',
        valueNum: 0,
        status: 'new',
        statusDays: 0,
        score: 0,
        source: '',
        owner: mineOnly ? 'me' : 'rk',
        team: const [],
        phone: '',
        email: '',
        website: '',
        industry: '',
        location: '',
        createdOn: '',
        time: '',
        lastFu: '',
        notif: 0,
      ),
    ];
  }

  @override
  Future<Lead?> createLead(Map<String, dynamic> fields) async => null;
}

/// Lets the FutureProviders resolve.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('LeadsRemoteDataSource.fetchLeadRows', () {
    test('My leads sends is_teams=true, All leads omits it', () async {
      final adapter = _PagingAdapter();
      final ds = LeadsRemoteDataSource(_apiWith(adapter));

      await ds.fetchLeadRows(mineOnly: true);
      expect(adapter.requests.single.queryParameters['is_teams'], true);

      adapter.requests.clear();
      await ds.fetchLeadRows();
      expect(adapter.requests.single.queryParameters.containsKey('is_teams'), isFalse);
    });

    test('follows every page and keeps the scope on each request', () async {
      final adapter = _PagingAdapter(pages: 3);
      final ds = LeadsRemoteDataSource(_apiWith(adapter));

      final rows = await ds.fetchLeadRows(mineOnly: true);

      expect(rows.length, 3, reason: 'one row per page, all pages walked');
      expect(adapter.requests.length, 3);
      // A page-2 request without the scope would widen the list mid-walk.
      for (final r in adapter.requests) {
        expect(r.queryParameters['is_teams'], true);
        expect(r.queryParameters['page_size'], 200); // server max_page_size
      }
      expect(adapter.requests.map((r) => r.queryParameters['page']).toList(),
          [null, 2, 3]);
    });
  });

  group('mock repository', () {
    test('mineOnly mirrors the server scope (owner or assignee is me)', () async {
      const repo = LeadsRepositoryImpl(LeadsMockDataSource());

      final all = await repo.getLeads();
      final mine = await repo.getLeads(mineOnly: true);

      expect(mine.length, lessThan(all.length));
      expect(mine.every((l) => l.isMine), isTrue);
    });
  });

  group('scope providers', () {
    test('the toggle fetches the entered scope; lookups stay org-wide', () async {
      final repo = _RecordingRepo();
      final container = ProviderContainer(
        overrides: [leadsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      // Default view is "My leads".
      container.listen(leadsListProvider, (_, __) {}, fireImmediately: true);
      await _settle();
      expect(repo.calls, [true]);
      expect(container.read(leadBaseProvider).single.id, 'MINE');

      // Switching to "All leads" issues a request rather than re-filtering.
      container.invalidate(leadsScopedProvider(const LeadListQuery()));
      container.read(leadTeamAllProvider.notifier).state = true;
      await _settle();
      expect(repo.calls, [true, false]);
      expect(container.read(leadBaseProvider).single.id, 'ALL');

      // Switching back re-queries too — no reuse of the earlier "mine" list.
      container.invalidate(leadsScopedProvider(const LeadListQuery(mineOnly: true)));
      container.read(leadTeamAllProvider.notifier).state = false;
      await _settle();
      expect(repo.calls, [true, false, true]);

      // Cross-screen lookups ignore the toggle: still the org-wide list.
      container.listen(leadsProvider, (_, __) {}, fireImmediately: true);
      await _settle();
      expect(container.read(leadsProvider).valueOrNull?.single.id, 'ALL');
    });
  });
}
