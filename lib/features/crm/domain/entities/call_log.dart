import 'package:equatable/equatable.dart';

/// A logged phone call against a lead (or customer) — one row of the Call log
/// tab. Maps `/crm/call-logs/`, where the direction, the missed flag and the
/// duration together decide how the row reads.
class CallLog extends Equatable {
  final String id;
  final String? leadId;

  /// `incoming` / `outgoing` — from the API's `type`.
  final String direction;

  /// The call rang out unanswered (`is_missed`).
  final bool isMissed;

  /// The call was answered and lasted a non-zero duration.
  final bool connected;

  /// Display line: "Connected · 3m 45s", "No answer" or "Missed call".
  final String outcome;

  /// Display timestamp: "Today, 9:32 AM" / "2 days ago, 11:04 AM".
  final String time;

  /// AI/manual call summary; `''` when the backend has none.
  final String summary;

  /// CDN recording URL; `''` when nothing was recorded.
  final String recordingUrl;

  const CallLog({
    required this.id,
    required this.leadId,
    required this.direction,
    required this.isMissed,
    required this.connected,
    required this.outcome,
    required this.time,
    this.summary = '',
    this.recordingUrl = '',
  });

  bool get isIncoming => direction == 'incoming';
  bool get hasRecording => recordingUrl.isNotEmpty;

  @override
  List<Object?> get props => [id];
}
