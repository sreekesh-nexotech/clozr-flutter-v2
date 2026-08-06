// `first_name` is required on create, but it is seeded `visible: false` on the
// lead detail layout and the UI only collects one "Lead name" box. So neither
// the schema-driven Add lead form nor the hand-written fallback could produce a
// valid payload — every create came back
//   400 {"first_name": ["This field is required."]}
// Verified live against the dev API, both before and after.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

class _Adapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(const {'lead_id': 'L1', 'lead_name': 'Schema Probe Lead'}),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('the name parts a create needs', () {
    test('splits the lead name on the first space', () {
      final out = LeadsRemoteDataSource.withCreateNameParts(
          const {'lead_name': 'Schema Probe Lead'});

      expect(out['first_name'], 'Schema');
      expect(out['last_name'], 'Probe Lead');
      expect(out['lead_name'], 'Schema Probe Lead', reason: 'kept as sent');
    });

    test('a single-word name sends no surname rather than an empty one', () {
      final out =
          LeadsRemoteDataSource.withCreateNameParts(const {'lead_name': 'Ishaan'});

      expect(out['first_name'], 'Ishaan');
      expect(out.containsKey('last_name'), isFalse);
    });

    test('anything the caller supplied explicitly wins', () {
      final out = LeadsRemoteDataSource.withCreateNameParts(const {
        'lead_name': 'Schema Probe Lead',
        'first_name': 'Given',
        'last_name': 'Surname',
      });

      expect(out['first_name'], 'Given');
      expect(out['last_name'], 'Surname');
    });

    test('a half-supplied pair still gets the missing half', () {
      final out = LeadsRemoteDataSource.withCreateNameParts(const {
        'lead_name': 'Schema Probe Lead',
        'first_name': 'Given',
      });

      expect(out['first_name'], 'Given');
      expect(out['last_name'], 'Probe Lead');
    });

    test('no lead name means nothing to derive from', () {
      final out = LeadsRemoteDataSource.withCreateNameParts(
          const {'organization_name': 'Probe Co'});

      expect(out.containsKey('first_name'), isFalse);
    });

    test('extra whitespace does not leak into the parts', () {
      final out = LeadsRemoteDataSource.withCreateNameParts(
          const {'lead_name': '  Schema   Probe  '});

      expect(out['first_name'], 'Schema');
      expect(out['last_name'], 'Probe');
    });
  });

  group('createLead', () {
    test('sends the derived parts, so the API accepts the payload', () async {
      final adapter = _Adapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
        ..httpClientAdapter = adapter;
      final ds = LeadsRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));

      await ds.createLead(const {
        'lead_name': 'Schema Probe Lead',
        'organization_name': 'Probe Co',
        'email': 'probe@example.com',
      });

      final sent = adapter.requests.single.data as Map;
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/crm/leads/');
      // The field whose absence produced the 400.
      expect(sent['first_name'], 'Schema');
      expect(sent['last_name'], 'Probe Lead');
      expect(sent['lead_name'], 'Schema Probe Lead');
    });

    test('blank values are still dropped rather than sent empty', () async {
      final adapter = _Adapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
        ..httpClientAdapter = adapter;
      final ds = LeadsRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));

      await ds.createLead(const {
        'lead_name': 'Ishaan',
        'organization_name': '',
        'email': '   ',
      });

      final sent = adapter.requests.single.data as Map;
      expect(sent.containsKey('organization_name'), isFalse);
      expect(sent.containsKey('email'), isFalse);
      expect(sent['first_name'], 'Ishaan');
    });
  });
}
