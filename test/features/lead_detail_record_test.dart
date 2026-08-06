// The detail screen reads the **record** endpoint, not a row from the list.
// The two are trimmed to different field configs: a list row carries no
// `lead_owner`, `email`, `mobile_no`, `whatsapp_no` or `territory` at all, so
// reusing one left the Owner & Assignees block showing "Unknown" and half the
// information rows empty. Fixtures below are the real dev-backend shapes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/application/providers/leads_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/domain/entities/lead.dart';
import 'package:clozrapp/features/crm/domain/repositories/leads_repository.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

/// A list row as `GET /crm/leads/` returns it under the default list config —
/// note what is *absent*.
const _listRow = {
  'lead_id': 'L1',
  'lead_name': 'Rahul Verma 48',
  'organization_name': 'OmniTech Services',
  'lead_score': 23,
  'status': 'New',
  'lead_source': {'name': 'Referral'},
  'products': <dynamic>[],
  'lead_value': 0.0,
  'activity': '2026-08-02T04:04:40Z',
  'assignees': <dynamic>[],
  'custom_fields': <String, dynamic>{},
};

/// The same lead from `GET /crm/leads/{id}/` under the detail config.
const _recordRow = {
  'lead_id': 'L1',
  'lead_name': 'Rahul Verma 48',
  'organization_name': 'OmniTech Services',
  'email': 'rahul.verma.47@example.com',
  'mobile_no': '+917045090267',
  'whatsapp_no': null,
  'territory': {'name': 'South'},
  'lead_score': 23,
  'status': 'New',
  'lead_source': {'name': 'Referral'},
  'lead_value': 0.0,
  'activity': '2026-08-02T04:04:40Z',
  'assignees': <dynamic>[],
  'lead_owner': {
    'user_id': 'u-admin',
    'email': 'admin@seed.acme.com',
    'full_name': 'Admin Acme',
    'is_active': true,
  },
  'custom_fields': <String, dynamic>{},
};

/// Answers the record endpoint and records the paths it was asked for.
class _RecordAdapter implements HttpClientAdapter {
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(_recordRow),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Serves the list from the trimmed row and the record from the full one.
class _SplitRepo implements LeadsRepository {
  int recordCalls = 0;

  @override
  Future<List<Lead>> getLeads({
    bool mineOnly = false,
    Map<String, dynamic> filters = const {},
  }) async =>
      LeadsRemoteDataSource.mapLeadRows([_listRow]);

  @override
  Future<Lead?> getLead(String id) async {
    recordCalls++;
    return LeadsRemoteDataSource.mapLead(Map<String, dynamic>.from(_recordRow));
  }

  @override
  Future<Lead?> updateLeadStatus(String leadId, String statusId) async => null;

  @override
  Future<List<CatalogOption>> getAssignableUsers(String leadId) async => const [];

  @override
  Future<Lead?> createLead(Map<String, dynamic> fields) async => null;

  @override
  Future<Lead?> updateLead(String leadId, Map<String, dynamic> fields) async =>
      null;

  @override
  Future<Map<String, dynamic>?> getLeadRow(String id) async => null;
}

Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('the two endpoints really do carry different fields', () {
    test('a list row has no owner, email, mobile or territory', () {
      final fromList = LeadsRemoteDataSource.mapLead(
          Map<String, dynamic>.from(_listRow))!;

      expect(fromList.owner, '', reason: 'this is what rendered as "Unknown"');
      expect(fromList.email, '');
      expect(fromList.phone, '');
      expect(fromList.whatsappNo, '');
      expect(fromList.territory, '');
    });

    test('the record row carries all of them', () {
      final fromRecord = LeadsRemoteDataSource.mapLead(
          Map<String, dynamic>.from(_recordRow))!;

      expect(fromRecord.owner, isNotEmpty);
      expect(fromRecord.email, 'rahul.verma.47@example.com');
      expect(fromRecord.phone, '+917045090267');
      expect(fromRecord.territory, 'South');
      // Genuinely null on this lead — empty, not missing.
      expect(fromRecord.whatsappNo, '');
    });
  });

  test('fetchLeadRow calls the record endpoint for that id', () async {
    final adapter = _RecordAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
      ..httpClientAdapter = adapter;
    final ds = LeadsRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));

    final row = await ds.fetchLeadRow('L1');

    expect(adapter.paths.single, '/crm/leads/L1/');
    expect(row!['lead_owner'], isA<Map>());
  });

  group('leadDetailProvider', () {
    test('fetches the record rather than reusing the list row', () async {
      final repo = _SplitRepo();
      final container = ProviderContainer(
        overrides: [leadsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      container.listen(leadDetailProvider('L1'), (_, __) {}, fireImmediately: true);
      await _settle();

      expect(repo.recordCalls, 1);
      final lead = container.read(leadDetailProvider('L1')).valueOrNull!;
      expect(lead.owner, isNotEmpty, reason: 'the owner block can now resolve');
      expect(lead.email, 'rahul.verma.47@example.com');
      expect(lead.territory, 'South');
    });

    test('the list row is still available as an instant seed', () async {
      final repo = _SplitRepo();
      final container = ProviderContainer(
        overrides: [leadsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      container.listen(leadsListProvider, (_, __) {}, fireImmediately: true);
      await _settle();

      // Present, so the page paints immediately — but thin, which is exactly
      // why the record fetch above has to happen.
      final seed = container.read(leadByIdProvider('L1'))!;
      expect(seed.name, 'Rahul Verma 48');
      expect(seed.owner, isEmpty);
    });
  });
}
