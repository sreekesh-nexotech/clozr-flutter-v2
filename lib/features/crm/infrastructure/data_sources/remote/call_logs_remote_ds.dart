import 'package:intl/intl.dart';

import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../domain/entities/call_log.dart';

final DateFormat _clock = DateFormat('h:mm a');
final DateFormat _dayMonth = DateFormat('d MMM');

/// Remote call logs (`/crm/call-logs/`). HTTP + JSON → [CallLog] mapping only;
/// caching lives in the API repository.
///
/// The list is always scoped to one record via the shared generic-relation
/// params (`related_to=lead&related_to_id=<lead_id>`) — there is no nested
/// `/leads/{id}/call-logs/` route.
class CallLogsRemoteDataSource {
  const CallLogsRemoteDataSource(this._api);

  final ApiService _api;

  /// Raw rows for one lead, following `next` up to a sane page cap. The
  /// repository caches these and maps them via [mapRows].
  Future<List<Map<String, dynamic>>> fetchCallLogRowsForLead(
      String leadId) async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; page <= 50; page++) {
      final body = await _api.get(ApiEndpoints.callLogs, query: {
        'related_to': 'lead',
        'related_to_id': leadId,
        'page_size': ApiConfig.defaultPageSize,
        if (page > 1) 'page': page,
      });
      final chunk = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      rows.addAll(chunk.results);
      if (!chunk.hasMore) break;
    }
    return rows;
  }

  /// Mapped call list for one lead (malformed rows are skipped, never fatal).
  Future<List<CallLog>> fetchCallLogsForLead(String leadId) async =>
      mapRows(await fetchCallLogRowsForLead(leadId));

  /// `POST /crm/call-logs/` — records an outgoing call against a lead.
  ///
  /// `related_to` and `related_to_id` are both-or-neither by contract, so they
  /// are always sent together. `telephony_medium: Manual` says the call was
  /// placed by hand from the device rather than through Twilio/Exotel.
  Future<void> createOutgoingCall({
    required String leadId,
    required String fromNumber,
    required String toNumber,
  }) =>
      _api.post(ApiEndpoints.callLogs, body: {
        'from_number': fromNumber,
        'to_number': toNumber,
        'type': 'Outgoing',
        'telephony_medium': 'Manual',
        'related_to': 'lead',
        'related_to_id': leadId,
      });

  // ── mapping (static so the repository and tests reuse it) ──

  /// Maps rows and sorts them newest-first.
  ///
  /// The sort is deliberately client-side: `/crm/call-logs/` accepts an
  /// `ordering` param without honouring it, and it returns rows oldest-first,
  /// which is the wrong way round for an activity feed.
  static List<CallLog> mapRows(List<Map<String, dynamic>> rows,
      {DateTime? now}) {
    final dated = <(DateTime?, CallLog)>[];
    for (final row in rows) {
      final log = callLogFromJson(row, now: now);
      if (log != null) dated.add((_startedAt(row), log));
    }
    dated.sort((a, b) {
      final x = a.$1, y = b.$1;
      if (x == null && y == null) return 0;
      if (x == null) return 1; // undated rows sink to the bottom
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return [for (final d in dated) d.$2];
  }

  /// One list row → [CallLog]. A row without a `crm_call_log_id` returns null
  /// (the caller skips it).
  static CallLog? callLogFromJson(Map<String, dynamic> json, {DateTime? now}) {
    final id = _str(json['crm_call_log_id']);
    if (id == null || id.isEmpty) return null;

    final started = _startedAt(json);
    final isMissed = json['is_missed'] == true;
    final duration = parseDuration(json['duration']);
    final connected = !isMissed && duration > Duration.zero;

    return CallLog(
      id: id,
      leadId: _str(json['related_to_model']) == 'lead'
          ? _str(json['related_to_object_id'])
          : null,
      direction:
          (_str(json['type']) ?? '').toLowerCase() == 'incoming'
              ? 'incoming'
              : 'outgoing',
      isMissed: isMissed,
      connected: connected,
      outcome: outcomeLabel(
          isMissed: isMissed, connected: connected, duration: duration),
      time: callTimeLabel(started, now: now),
      summary: _str(json['call_summary'])?.trim() ?? '',
      recordingUrl:
          _str(json['cdn_recording_url']) ?? _str(json['recording_url']) ?? '',
    );
  }

  /// "Connected · 3m 45s" / "No answer" / "Missed call".
  static String outcomeLabel({
    required bool isMissed,
    required bool connected,
    required Duration duration,
  }) {
    if (isMissed) return 'Missed call';
    if (!connected) return 'No answer';
    return 'Connected · ${durationLabel(duration)}';
  }

  /// "1h 2m" / "3m 45s" / "45s".
  static String durationLabel(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Django `DurationField` text → [Duration]. Accepts `"HH:MM:SS"`,
  /// `"HH:MM:SS.ffffff"` and `"D HH:MM:SS"`; anything else is zero.
  static Duration parseDuration(Object? value) {
    if (value is num) return Duration(seconds: value.round());
    final raw = _str(value)?.trim();
    if (raw == null || raw.isEmpty) return Duration.zero;

    var days = 0;
    var clock = raw;
    final space = raw.indexOf(' ');
    if (space > 0) {
      days = int.tryParse(raw.substring(0, space).trim()) ?? 0;
      clock = raw.substring(space + 1).trim();
    }

    final parts = clock.split(':');
    if (parts.length != 3) return Duration.zero;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = double.tryParse(parts[2]);
    if (h == null || m == null || s == null) return Duration.zero;
    return Duration(
      days: days,
      hours: h,
      minutes: m,
      milliseconds: (s * 1000).round(),
    );
  }

  /// "Today, 9:32 AM" / "Yesterday, 5:10 PM" / "2 days ago, 11:04 AM" /
  /// "12 Apr, 3:22 PM". Empty when the row carries no timestamp.
  static String callTimeLabel(DateTime? time, {DateTime? now}) {
    if (time == null) return '';
    final local = time.toLocal();
    final ref = (now ?? DateTime.now()).toLocal();
    final today = DateTime(ref.year, ref.month, ref.day);
    final day = DateTime(local.year, local.month, local.day);
    final days = today.difference(day).inDays;

    final String label;
    if (days <= 0) {
      label = 'Today';
    } else if (days == 1) {
      label = 'Yesterday';
    } else if (days < 7) {
      label = '$days days ago';
    } else {
      label = _dayMonth.format(local);
    }
    return '$label, ${_clock.format(local)}';
  }

  /// The row's timestamp — `start_time`, falling back to `created_at`.
  static DateTime? _startedAt(Map<String, dynamic> json) =>
      parseApiDate(json['start_time']) ?? parseApiDate(json['created_at']);
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
