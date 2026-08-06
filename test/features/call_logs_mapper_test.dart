import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/call_logs_remote_ds.dart';

/// Captures the request and echoes a created call log.
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
      jsonEncode({'crm_call_log_id': 'c1'}),
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
  const leadId = 'lead-uuid-1';

  // Fixed "now" so the relative time labels are deterministic.
  final now = DateTime(2026, 8, 6, 14, 0);

  Map<String, dynamic> row({
    String id = 'call-uuid-1',
    String type = 'Outgoing',
    Object? duration = '00:03:45',
    bool isMissed = false,
    Object? startTime,
  }) =>
      {
        'crm_call_log_id': id,
        'from_number': '+911234567890',
        'to_number': '+919876543210',
        'type': type,
        'duration': duration,
        'is_missed': isMissed,
        'start_time':
            startTime ?? DateTime(2026, 8, 6, 9, 32).toIso8601String(),
        'call_summary': 'Discussed scope and timeline.',
        'recording_url': null,
        'cdn_recording_url': null,
        'related_to_model': 'lead',
        'related_to_object_id': leadId,
      };

  group('callLogFromJson', () {
    test('maps a connected outgoing call', () {
      final log = CallLogsRemoteDataSource.callLogFromJson(row(), now: now)!;

      expect(log.id, 'call-uuid-1');
      expect(log.leadId, leadId);
      expect(log.direction, 'outgoing');
      expect(log.isIncoming, isFalse);
      expect(log.isMissed, isFalse);
      expect(log.connected, isTrue);
      expect(log.outcome, 'Connected · 3m 45s');
      expect(log.time, 'Today, 9:32 AM');
      expect(log.summary, 'Discussed scope and timeline.');
      expect(log.hasRecording, isFalse);
    });

    test('a zero-duration call reads as "No answer", not "Connected · 0s"', () {
      final log = CallLogsRemoteDataSource.callLogFromJson(
          row(duration: '00:00:00'),
          now: now)!;

      expect(log.connected, isFalse);
      expect(log.outcome, 'No answer');
    });

    test('is_missed wins over any duration on the row', () {
      final log = CallLogsRemoteDataSource.callLogFromJson(
          row(isMissed: true, duration: '00:01:00'),
          now: now)!;

      expect(log.isMissed, isTrue);
      expect(log.connected, isFalse);
      expect(log.outcome, 'Missed call');
    });

    test('an incoming call maps its direction', () {
      final log = CallLogsRemoteDataSource.callLogFromJson(
          row(type: 'Incoming'),
          now: now)!;

      expect(log.direction, 'incoming');
      expect(log.isIncoming, isTrue);
    });

    test('the CDN recording URL is preferred over the raw one', () {
      final withBoth = row()
        ..['recording_url'] = 'https://raw.example.com/a.mp3'
        ..['cdn_recording_url'] = 'https://cdn.example.com/a.mp3';
      final log = CallLogsRemoteDataSource.callLogFromJson(withBoth, now: now)!;

      expect(log.recordingUrl, 'https://cdn.example.com/a.mp3');
      expect(log.hasRecording, isTrue);
    });

    test('a row without an id is skipped rather than fatal', () {
      expect(
        CallLogsRemoteDataSource.callLogFromJson({'type': 'Outgoing'}),
        isNull,
      );
    });

    test('missing and malformed fields never throw', () {
      final log = CallLogsRemoteDataSource.callLogFromJson(
          {'crm_call_log_id': 'x', 'duration': 'not-a-duration'},
          now: now)!;

      expect(log.direction, 'outgoing'); // default when `type` is absent
      expect(log.outcome, 'No answer');
      expect(log.time, ''); // no timestamp on the row
      expect(log.summary, '');
      expect(log.leadId, isNull); // not linked to a lead
    });
  });

  group('parseDuration', () {
    test('parses HH:MM:SS', () {
      expect(CallLogsRemoteDataSource.parseDuration('00:03:45'),
          const Duration(minutes: 3, seconds: 45));
    });

    test('parses fractional seconds', () {
      expect(CallLogsRemoteDataSource.parseDuration('00:00:02.500000'),
          const Duration(seconds: 2, milliseconds: 500));
    });

    test('parses the "D HH:MM:SS" form Django emits past 24h', () {
      expect(CallLogsRemoteDataSource.parseDuration('1 02:00:00'),
          const Duration(days: 1, hours: 2));
    });

    test('null and junk are zero, never a throw', () {
      expect(CallLogsRemoteDataSource.parseDuration(null), Duration.zero);
      expect(CallLogsRemoteDataSource.parseDuration('abc'), Duration.zero);
      expect(CallLogsRemoteDataSource.parseDuration('12:34'), Duration.zero);
    });
  });

  group('durationLabel', () {
    test('formats hours, minutes and seconds', () {
      expect(CallLogsRemoteDataSource.durationLabel(const Duration(seconds: 45)),
          '45s');
      expect(
          CallLogsRemoteDataSource.durationLabel(
              const Duration(minutes: 3, seconds: 45)),
          '3m 45s');
      expect(
          CallLogsRemoteDataSource.durationLabel(
              const Duration(hours: 1, minutes: 2, seconds: 30)),
          '1h 2m');
    });
  });

  group('callTimeLabel', () {
    test('uses Today / Yesterday / N days ago / date', () {
      String at(DateTime d) =>
          CallLogsRemoteDataSource.callTimeLabel(d, now: now);

      expect(at(DateTime(2026, 8, 6, 9, 32)), 'Today, 9:32 AM');
      expect(at(DateTime(2026, 8, 5, 17, 10)), 'Yesterday, 5:10 PM');
      expect(at(DateTime(2026, 8, 4, 11, 4)), '2 days ago, 11:04 AM');
      expect(at(DateTime(2026, 7, 12, 15, 22)), '12 Jul, 3:22 PM');
    });

    test('null yields an empty label', () {
      expect(CallLogsRemoteDataSource.callTimeLabel(null, now: now), '');
    });
  });

  group('mapRows', () {
    test('sorts newest-first regardless of the order the API returned', () {
      // The endpoint hands back oldest-first, which is the wrong way round for
      // an activity feed.
      final rows = [
        row(id: 'old', startTime: DateTime(2026, 8, 1, 9).toIso8601String()),
        row(id: 'new', startTime: DateTime(2026, 8, 6, 9).toIso8601String()),
        row(id: 'mid', startTime: DateTime(2026, 8, 4, 9).toIso8601String()),
      ];

      final mapped = CallLogsRemoteDataSource.mapRows(rows, now: now);

      expect(mapped.map((c) => c.id), ['new', 'mid', 'old']);
    });

    test('undated rows sink to the bottom instead of disappearing', () {
      final rows = [
        {'crm_call_log_id': 'undated'},
        row(id: 'dated'),
      ];

      final mapped = CallLogsRemoteDataSource.mapRows(rows, now: now);

      expect(mapped.map((c) => c.id), ['dated', 'undated']);
    });

    test('malformed rows are dropped, the rest still map', () {
      final mapped = CallLogsRemoteDataSource.mapRows([
        row(id: 'good'),
        {'no_id': true},
      ], now: now);

      expect(mapped.map((c) => c.id), ['good']);
    });
  });

  group('logging an outgoing call', () {
    test('posts the contract the API documents', () async {
      final adapter = _CaptureAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
        ..httpClientAdapter = adapter;
      final ds = CallLogsRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));

      await ds.createOutgoingCall(
        leadId: leadId,
        fromNumber: '+911111111111',
        toNumber: '+919999999999',
      );

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/crm/call-logs/');
      expect(req.data, {
        'from_number': '+911111111111', // required — the API 400s without it
        'to_number': '+919999999999',
        'type': 'Outgoing',
        'telephony_medium': 'Manual',
        // Both-or-neither by contract, so they always travel together.
        'related_to': 'lead',
        'related_to_id': leadId,
      });
    });
  });

  group('logging a call by hand (the Log call sheet)', () {
    CallLogsRemoteDataSource dsWith(_CaptureAdapter adapter) {
      final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
        ..httpClientAdapter = adapter;
      return CallLogsRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));
    }

    test('sends direction, missed flag and duration', () async {
      final adapter = _CaptureAdapter();
      final start = DateTime.utc(2026, 8, 6, 9, 32);

      await dsWith(adapter).createManualCall(
        leadId: leadId,
        fromNumber: '+911111111111',
        toNumber: '+919999999999',
        incoming: true,
        isMissed: false,
        duration: const Duration(minutes: 4, seconds: 12),
        startTime: start,
      );

      final body = adapter.requests.single.data as Map<String, dynamic>;
      expect(body['type'], 'Incoming');
      expect(body['is_missed'], isFalse);
      expect(body['duration'], '00:04:12');
      expect(body['telephony_medium'], 'Manual');
      expect(body['related_to'], 'lead');
      expect(body['related_to_id'], leadId);
    });

    test('derives end_time from start + duration, never before start', () async {
      final adapter = _CaptureAdapter();
      final start = DateTime.utc(2026, 8, 6, 9, 32);

      await dsWith(adapter).createManualCall(
        leadId: leadId,
        fromNumber: '+911111111111',
        toNumber: '+919999999999',
        incoming: false,
        isMissed: false,
        duration: const Duration(minutes: 4, seconds: 12),
        startTime: start,
      );

      final body = adapter.requests.single.data as Map<String, dynamic>;
      final startSent = DateTime.parse(body['start_time'] as String);
      final endSent = DateTime.parse(body['end_time'] as String);
      expect(endSent.isBefore(startSent), isFalse); // the API 400s on this
      expect(endSent.difference(startSent), const Duration(minutes: 4, seconds: 12));
    });

    test('a missed call sends a zero duration', () async {
      final adapter = _CaptureAdapter();

      await dsWith(adapter).createManualCall(
        leadId: leadId,
        fromNumber: '+911111111111',
        toNumber: '+919999999999',
        incoming: true,
        isMissed: true,
        duration: Duration.zero,
        startTime: DateTime.utc(2026, 8, 6, 9),
      );

      final body = adapter.requests.single.data as Map<String, dynamic>;
      expect(body['is_missed'], isTrue);
      expect(body['duration'], '00:00:00');
    });

    test('never sends call_summary — the API drops it silently', () async {
      final adapter = _CaptureAdapter();

      await dsWith(adapter).createManualCall(
        leadId: leadId,
        fromNumber: '+911111111111',
        toNumber: '+919999999999',
        incoming: false,
        isMissed: false,
      );

      final body = adapter.requests.single.data as Map<String, dynamic>;
      expect(body.containsKey('call_summary'), isFalse);
    });
  });

  group('hhmmss', () {
    test('pads every component to two digits', () {
      expect(CallLogsRemoteDataSource.hhmmss(Duration.zero), '00:00:00');
      expect(CallLogsRemoteDataSource.hhmmss(const Duration(seconds: 5)), '00:00:05');
      expect(CallLogsRemoteDataSource.hhmmss(const Duration(minutes: 4, seconds: 12)),
          '00:04:12');
      expect(
          CallLogsRemoteDataSource.hhmmss(
              const Duration(hours: 1, minutes: 2, seconds: 3)),
          '01:02:03');
    });

    test('round-trips through parseDuration', () {
      const d = Duration(hours: 2, minutes: 7, seconds: 33);
      expect(
        CallLogsRemoteDataSource.parseDuration(CallLogsRemoteDataSource.hhmmss(d)),
        d,
      );
    });
  });
}
