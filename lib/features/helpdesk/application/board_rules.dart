import '../domain/entities/issue_summary.dart';

/// The Support Overview's card and column wording, ported from the webapp's
/// `SupportOverviewScreen`, `toBoardMiniCard`, `slaCountdownChip` and
/// `ticketFormat.ts`. Pure, so it is unit-tested.

/// The SLA window the board asks the server for (`due_soon_minutes`), and the
/// label of its column: "Due < 60m".
const boardDueSoonMinutes = 60;
const boardDueSoonLabel = 'Due < ${boardDueSoonMinutes}m';

/// The "Open tickets" definition (webapp `OPEN_TICKETS_TIP`).
const openTicketsTip = 'Open = tickets not yet resolved or closed, in your scope';

/// The panels' info text.
String slaWatchInfo({required bool hasNoSla}) => hasNoSla
    ? "Tickets ordered by SLA urgency. A ticket's SLA comes from its customer; tickets without one are listed under No SLA."
    : "Tickets ordered by SLA urgency. A ticket's SLA comes from its customer.";
const workloadInfo = 'Active tickets per agent. Resolved and closed tickets are not shown.';
const pipelineInfo = 'Where active work sits, one lane per status configured for this org.';

/// The No SLA column's note when the server sent only a count.
const noSlaCountOnlyNote = 'Open tickets with no SLA deadline — usually raised without a customer.';

/// How a card's pill reads: no SLA, paused, breached (red), at risk (amber,
/// due within 24h) or on track (neutral).
enum BoardPillTone { noSla, paused, breached, atRisk, onTrack }

/// The card pill — webapp `slaState` + `formatSlaRemaining`: "No SLA",
/// "Paused", "Overdue 4h 12m", "1d 3h left".
({String label, BoardPillTone tone}) boardCardPill(SummaryCard c) {
  final left = c.slaRemainingSeconds;
  if (left == null) return (label: 'No SLA', tone: BoardPillTone.noSla);
  if (c.slaPaused) return (label: 'Paused', tone: BoardPillTone.paused);
  final abs = left.abs();
  final d = abs ~/ 86400, h = (abs % 86400) ~/ 3600, m = (abs % 3600) ~/ 60;
  final span = d > 0 ? '${d}d ${h}h' : (h > 0 ? '${h}h ${m}m' : '${m}m');
  if (left < 0) return (label: 'Overdue $span', tone: BoardPillTone.breached);
  return (label: '$span left', tone: left <= 86400 ? BoardPillTone.atRisk : BoardPillTone.onTrack);
}

/// The Pipeline card's age: "Just now", "5m", "3h", "2d" (webapp `timeAgo`
/// without " ago").
String boardCardAge(DateTime? createdAt, {DateTime? now}) {
  if (createdAt == null) return '';
  final secs = (now ?? DateTime.now()).difference(createdAt).inSeconds;
  if (secs < 60) return 'Just now';
  if (secs < 3600) return '${secs ~/ 60}m';
  if (secs < 86400) return '${secs ~/ 3600}h';
  return '${secs ~/ 86400}d';
}

/// Initials for a card / column avatar; "–" when unassigned.
String boardInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '–';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

/// The column footer: "+3 more →", or "View in tickets →" when the server
/// sent only a count. Null when every ticket is on screen.
String? boardMoreLabel(int total, int shown) {
  if (total <= shown) return null;
  return shown == 0 ? 'View in tickets →' : '+${total - shown} more →';
}

/// The info toast shown on the Tickets list after a footer tap.
String bucketMoreToast(int total, String label) => 'Tickets list — $total ${label.toLowerCase()} tickets';
String workloadMoreToast(WorkloadColumn col) => col.isUnassigned
    ? 'Unassigned tickets — use the Assignee filter'
    : 'Tickets assigned to ${col.agentName.split(' ').first}';
