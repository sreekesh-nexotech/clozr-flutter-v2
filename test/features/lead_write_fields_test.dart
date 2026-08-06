import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

/// Captures the request and echoes a lead row back.
class _CaptureAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'lead_id': 'lead-uuid-1', 'lead_name': 'Nitin Mishra'}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('leadWriteFields', () {
    test('sends the contact number as mobile_no, not phone', () {
      // Verified against a live org: `phone` is accepted, echoed back in the
      // response, and never stored — the serializer's contact field is
      // `mobile_no`.
      final fields = LeadsRemoteDataSource.leadWriteFields(
        name: 'Nitin Mishra',
        company: 'SwiftEdge',
        email: 'n@example.com',
        phone: '+919000011111',
        website: 'https://swiftedge.example.com',
      );

      expect(fields['mobile_no'], '+919000011111');
      expect(fields.containsKey('phone'), isFalse);
    });

    test('never sends purpose — Lead has no such field', () {
      final fields = LeadsRemoteDataSource.leadWriteFields(
        name: 'Nitin Mishra',
        company: '',
        email: '',
        phone: '',
        website: '',
      );

      expect(fields.containsKey('purpose'), isFalse);
    });

    test('trims every value', () {
      final fields = LeadsRemoteDataSource.leadWriteFields(
        name: '  Nitin Mishra  ',
        company: ' SwiftEdge ',
        email: ' n@example.com ',
        phone: ' +919000011111 ',
        website: ' https://x.example.com ',
      );

      expect(fields['lead_name'], 'Nitin Mishra');
      expect(fields['organization_name'], 'SwiftEdge');
      expect(fields['email'], 'n@example.com');
      expect(fields['mobile_no'], '+919000011111');
      expect(fields['website'], 'https://x.example.com');
    });

    test('keeps blank values so an emptied box clears the field', () {
      // The edit form is prefilled from the record, so a box the user cleared
      // is an instruction — dropping it would silently ignore the edit.
      final fields = LeadsRemoteDataSource.leadWriteFields(
        name: 'Nitin Mishra',
        company: '',
        email: '',
        phone: '',
        website: '',
      );

      expect(fields.keys.toSet(), {
        'lead_name',
        'organization_name',
        'email',
        'mobile_no',
        'website',
      });
      expect(fields['company'], isNull);
      expect(fields['email'], '');
    });
  });

  group('updateLead', () {
    test('PATCHes the lead detail route with the fields verbatim', () async {
      final adapter = _CaptureAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
        ..httpClientAdapter = adapter;
      final ds = LeadsRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));

      final fields = LeadsRemoteDataSource.leadWriteFields(
        name: 'Nitin Mishra',
        company: 'SwiftEdge',
        email: 'n@example.com',
        phone: '+919000011111',
        website: '',
      );
      await ds.updateLead('lead-uuid-1', fields);

      final req = adapter.requests.single;
      expect(req.method, 'PATCH');
      expect(req.path, '/crm/leads/lead-uuid-1/');
      // Blanks survive the trip — this is an update, not a create.
      expect(req.data, fields);
      expect((req.data as Map)['website'], '');
    });

    test('an unexpected response shape yields null rather than throwing',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
        ..httpClientAdapter = _ListAdapter();
      final ds = LeadsRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));

      expect(await ds.updateLead('lead-uuid-1', const {}), isNull);
    });
  });
}

/// Returns a JSON array where the caller expects an object.
class _ListAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        jsonEncode([1, 2, 3]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}
