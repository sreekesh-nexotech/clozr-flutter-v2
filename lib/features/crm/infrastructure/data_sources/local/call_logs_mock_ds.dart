import '../../../domain/entities/call_log.dart';

/// Static call-log seed — a 1:1 port of the four rows the Call log tab used to
/// hardcode in `lead_detail_screen.dart`.
///
/// The prototype showed the same four calls on every lead, so this seed is not
/// keyed by lead id either; only the API path is genuinely per-lead.
class CallLogsMockDataSource {
  const CallLogsMockDataSource();

  List<CallLog> fetchCallLogsForLead(String leadId) => [
        CallLog(id: 'CL-$leadId-1', leadId: leadId, direction: 'outgoing', isMissed: false, connected: true, outcome: 'Connected · 4m 12s', time: 'Today, 9:32 AM', summary: 'Discussed scope and timeline.'),
        CallLog(id: 'CL-$leadId-2', leadId: leadId, direction: 'outgoing', isMissed: false, connected: false, outcome: 'No answer', time: 'Yesterday, 5:10 PM'),
        CallLog(id: 'CL-$leadId-3', leadId: leadId, direction: 'incoming', isMissed: false, connected: true, outcome: 'Connected · 2m 40s', time: '2 days ago, 11:04 AM'),
        CallLog(id: 'CL-$leadId-4', leadId: leadId, direction: 'incoming', isMissed: true, connected: false, outcome: 'Missed call', time: '4 days ago, 3:22 PM'),
      ];
}
