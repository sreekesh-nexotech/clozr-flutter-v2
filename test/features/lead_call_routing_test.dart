// Which way the Call button places a call. Two routes exist because the
// backend has no single "call this lead" endpoint: Exotel click-to-call when
// the org has telephony connected, the device dialler otherwise.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/application/providers/lead_call_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/call_log.dart';
import 'package:clozrapp/features/crm/domain/entities/exotel_status.dart';
import 'package:clozrapp/features/crm/domain/repositories/call_logs_repository.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/exotel_remote_ds.dart';

const _leadId = 'lead-1';
const _to = '+919876543210';
const _me = '+911111111111';

/// Answers the Exotel call endpoint with either success or a refusal.
class _ExotelAdapter implements HttpClientAdapter {
  _ExotelAdapter({this.refuseWith});

  /// The 400 body Exotel returns when it cannot take the call.
  final String? refuseWith;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (refuseWith != null) {
      return ResponseBody.fromString(
        jsonEncode({'code': 400, 'message': refuseWith}),
        400,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'call_sid': 'sid1', 'call_log_id': 'cl1', 'status': 'Ringing'}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RecordingLogs implements CallLogsRepository {
  final List<Map<String, String>> logged = [];
  bool throwOnLog = false;

  @override
  Future<List<CallLog>> getCallLogsForLead(String leadId) async => const [];

  @override
  Future<void> logOutgoingCall({
    required String leadId,
    required String fromNumber,
    required String toNumber,
  }) async {
    if (throwOnLog) throw Exception('nope');
    logged.add({'lead': leadId, 'from': fromNumber, 'to': toNumber});
  }
}

ExotelRemoteDataSource _exotelWith(_ExotelAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
    ..httpClientAdapter = adapter;
  return ExotelRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));
}

void main() {
  late List<Uri> dialled;
  Future<bool> okDialler(Uri uri) async {
    dialled.add(uri);
    return true;
  }

  setUp(() => dialled = []);

  LeadCallService service({
    ExotelRemoteDataSource? exotel,
    required CallLogsRepository logs,
    Dialler? dialler,
    String myNumber = _me,
  }) =>
      LeadCallService(
        exotel: exotel,
        callLogs: logs,
        dialler: dialler ?? okDialler,
        myNumber: myNumber,
      );

  group('Exotel route', () {
    test('a connected org calls through Exotel and never opens the dialler', () async {
      final adapter = _ExotelAdapter();
      final logs = _RecordingLogs();
      final out = await service(exotel: _exotelWith(adapter), logs: logs).call(
        leadId: _leadId,
        toNumber: _to,
        status: const ExotelStatus(enabled: true, configured: true),
      );

      expect(out.result, LeadCallResult.ringingViaExotel);
      expect(dialled, isEmpty, reason: 'Exotel rings the agent; nothing to dial');
      // The server writes the call log itself — posting ours too would double it.
      expect(logs.logged, isEmpty);

      final req = adapter.requests.single;
      expect(req.path, '/crm/exotel/call/');
      expect(req.data, {
        'to_number': _to,
        'related_to': 'lead',
        'related_to_id': _leadId,
      });
    });

    test('enabled but unconfigured is not usable — goes to the dialler', () async {
      final logs = _RecordingLogs();
      final adapter = _ExotelAdapter();
      final out = await service(exotel: _exotelWith(adapter), logs: logs).call(
        leadId: _leadId,
        toNumber: _to,
        // Dialling this would 400 "not fully configured", so it is not tried.
        status: const ExotelStatus(enabled: true, configured: false),
      );

      expect(out.result, LeadCallResult.dialledAndLogged);
      expect(adapter.requests, isEmpty);
      expect(dialled.single.toString(), 'tel:$_to');
    });

    test('a refusal falls back to the dialler — no call was placed', () async {
      final logs = _RecordingLogs();
      final out = await service(
        exotel: _exotelWith(_ExotelAdapter(
            refuseWith: 'You are not configured as a telephony agent')),
        logs: logs,
      ).call(
        leadId: _leadId,
        toNumber: _to,
        status: const ExotelStatus(enabled: true, configured: true),
      );

      expect(out.result, LeadCallResult.dialledAndLogged);
      expect(dialled, hasLength(1));
      expect(logs.logged, hasLength(1));
      // Exotel was expected to work, so the reason is surfaced.
      expect(out.message, contains('telephony agent'));
    });
  });

  group('unknown status', () {
    test('tries Exotel anyway — /status/ is settings-gated for sales users', () async {
      final adapter = _ExotelAdapter();
      final out = await service(exotel: _exotelWith(adapter), logs: _RecordingLogs())
          .call(leadId: _leadId, toNumber: _to, status: const ExotelStatus.unknown());

      expect(out.result, LeadCallResult.ringingViaExotel);
      expect(adapter.requests, hasLength(1));
    });

    test('falls back quietly when it is refused — no scary message', () async {
      final out = await service(
        exotel: _exotelWith(_ExotelAdapter(refuseWith: 'Exotel integration is disabled')),
        logs: _RecordingLogs(),
      ).call(leadId: _leadId, toNumber: _to, status: const ExotelStatus.unknown());

      expect(out.result, LeadCallResult.dialledAndLogged);
      expect(out.message, isNull, reason: 'normal for an org without Exotel');
    });
  });

  group('dialler route', () {
    test('an org with telephony off dials and logs, never touching Exotel', () async {
      final adapter = _ExotelAdapter();
      final logs = _RecordingLogs();
      final out = await service(exotel: _exotelWith(adapter), logs: logs)
          .call(leadId: _leadId, toNumber: _to, status: const ExotelStatus.off());

      expect(out.result, LeadCallResult.dialledAndLogged);
      expect(adapter.requests, isEmpty);
      expect(logs.logged.single, {'lead': _leadId, 'from': _me, 'to': _to});
    });

    test('mock mode (no Exotel data source) dials', () async {
      final out = await service(logs: _RecordingLogs())
          .call(leadId: _leadId, toNumber: _to, status: const ExotelStatus.off());
      expect(out.result, LeadCallResult.dialledAndLogged);
    });

    test('no caller number on the profile: dials, cannot log', () async {
      final logs = _RecordingLogs();
      final out = await service(logs: logs, myNumber: '  ').call(
          leadId: _leadId, toNumber: _to, status: const ExotelStatus.off());

      expect(out.result, LeadCallResult.dialledNotLogged);
      expect(dialled, hasLength(1));
      // from_number is required by the API; inventing one would falsify history.
      expect(logs.logged, isEmpty);
    });

    test('a rejected log still leaves the call placed', () async {
      final logs = _RecordingLogs()..throwOnLog = true;
      final out = await service(logs: logs)
          .call(leadId: _leadId, toNumber: _to, status: const ExotelStatus.off());
      expect(out.result, LeadCallResult.dialledLogFailed);
      expect(dialled, hasLength(1));
    });
  });

  group('nothing to call', () {
    test('a lead with no number never dials', () async {
      final out = await service(logs: _RecordingLogs())
          .call(leadId: _leadId, toNumber: '   ', status: const ExotelStatus.off());
      expect(out.result, LeadCallResult.noNumber);
      expect(dialled, isEmpty);
    });

    test('a device that cannot dial reports it', () async {
      final out = await service(logs: _RecordingLogs(), dialler: (_) async => false)
          .call(leadId: _leadId, toNumber: _to, status: const ExotelStatus.off());
      expect(out.result, LeadCallResult.diallerUnavailable);
    });
  });

  group('status parsing', () {
    test('unknown is not the same as off', () {
      expect(const ExotelStatus.unknown().known, isFalse);
      expect(const ExotelStatus.off().known, isTrue);
      expect(const ExotelStatus.unknown().usable, isFalse);
    });

    test('both flags must hold to be usable', () {
      expect(const ExotelStatus(enabled: true, configured: true).usable, isTrue);
      expect(const ExotelStatus(enabled: true, configured: false).usable, isFalse);
      expect(const ExotelStatus(enabled: false, configured: true).usable, isFalse);
    });
  });
}
