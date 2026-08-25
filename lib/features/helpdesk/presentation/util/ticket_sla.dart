import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/api_config.dart';
import '../../domain/entities/ticket.dart';

/// Pure SLA / breach computations ported from the prototype's helpdesk
/// view-models.
///
/// The two anchors below were **fixed instants** on 09 Jul 2026 — 09:00 for the
/// tickets list and detail banner, 09:41 for the Support Overview board and the
/// home dashboard — so the design's screenshots reproduced exactly.
///
/// Against a real backend that froze every SLA figure in time: buckets, the
/// "Overdue 3h 12m" pills and the stat strip were all measured from July 9th,
/// so a ticket due last week still read as on track. They now follow the real
/// clock whenever there is an API, and stay frozen in mock mode, where the seed
/// records are dated relative to that day and would otherwise all read as
/// breached. Same contract as `kFilterToday`.
final DateTime _kMockNowList = DateTime.parse('2026-07-09T09:00:00');
final DateTime _kMockNowBoard = DateTime.parse('2026-07-09T09:41:00');

DateTime get kNowList => ApiConfig.apiEnabled ? DateTime.now() : _kMockNowList;
DateTime get kNowBoard => ApiConfig.apiEnabled ? DateTime.now() : _kMockNowBoard;

/// End of the day [kNowBoard] falls in — the boundary for the "Due today"
/// bucket. Derived so it tracks the anchor instead of naming a fixed date.
DateTime get kEod {
  final n = kNowBoard;
  return DateTime(n.year, n.month, n.day, 23, 59, 59);
}

/// Priority → pill colour (`PROJPRI`) used by the list/detail priority pill.
/// Urgent is not in the map, falling back to muted grey, matching the design.
Color ticketPriPillColor(String pri) => const {
      'High': AppColors.error,
      'Medium': AppColors.warningDeep,
      'Low': AppColors.success,
    }[pri] ??
    AppColors.textMuted;

/// The priorities `/crm/issues/` actually accepts and reports
/// (`admin_helpdesk_dashboard.md` §3, verified live — all four are in use).
///
/// One list, because the three that existed disagreed: the create form offered
/// High/Medium/Low, the edit form offered Urgent/High/Medium/Low — `Urgent` is
/// not a value this API has — and the dashboard's resolved grid iterated
/// High/Medium/Low, so **Critical tickets were missing from it entirely**.
const kTicketPriorities = ['Critical', 'High', 'Medium', 'Low'];

/// Priority → dot / donut colour (`hhPRI`) used by the dashboard + board dots.
Color ticketPriDotColor(String pri) => const {
      'Urgent': AppColors.error,
      'High': AppColors.warning,
      'Medium': AppColors.blueBright,
      'Low': AppColors.textMuted,
    }[pri] ??
    AppColors.textMuted;

String fmtLeft(int ms) {
  final abs = ms.abs();
  final d = abs ~/ 86400000;
  final h = (abs % 86400000) ~/ 3600000;
  final m = (abs % 3600000) ~/ 60000;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

int? _dueMs(Ticket t) {
  final iso = (t.responded == null && t.respByISO != null) ? t.respByISO : t.resolveByISO;
  if (iso == null) return null;
  return DateTime.parse(iso).millisecondsSinceEpoch;
}

/// The list-card SLA chip: next applicable target, tinted by urgency.
class SlaChip {
  final String text;
  final Color tone;
  final Color bg;
  final IconData icon;
  const SlaChip(this.text, this.tone, this.bg, this.icon);
}

SlaChip ticketListSlaChip(Ticket t) {
  final now = kNowList.millisecondsSinceEpoch;
  if (t.status == 'pending') {
    return const SlaChip('Paused', AppColors.textMuted2, AppColors.bgChipGrey, PhosphorIconsFill.pause);
  }
  if (t.status == 'resolved' || t.status == 'closed') {
    return const SlaChip('Resolved', AppColors.success, AppColors.tintGreen, PhosphorIconsFill.checkCircle);
  }
  if (t.responded == null && t.respByISO != null) {
    final ms = DateTime.parse(t.respByISO!).millisecondsSinceEpoch - now;
    if (ms < 0) return SlaChip('Overdue ${fmtLeft(ms)}', AppColors.error, AppColors.tintRed, PhosphorIconsFill.warningCircle);
    return SlaChip('Respond by ${t.respByLabel ?? ''}', AppColors.textMuted2, AppColors.bgChipGrey, PhosphorIconsRegular.clock);
  }
  if (t.resolveByISO != null) {
    final ms = DateTime.parse(t.resolveByISO!).millisecondsSinceEpoch - now;
    if (ms < 0) return SlaChip('Overdue ${fmtLeft(ms)}', AppColors.error, AppColors.tintRed, PhosphorIconsFill.warningCircle);
    return SlaChip('Resolve by ${t.resolveByLabel ?? ''}', AppColors.textMuted2, AppColors.bgChipGrey, PhosphorIconsRegular.clock);
  }
  return const SlaChip('—', AppColors.textMuted2, AppColors.bgChipGrey, PhosphorIconsRegular.clock);
}

/// Whether the ticket is breaching within the next hour (the "Breaching soon"
/// chip filter). Uses the list anchor (09:00).
bool ticketBreaching(Ticket t) {
  if (t.status == 'pending' || t.status == 'resolved' || t.status == 'closed') return false;
  final iso = (t.responded == null && t.respByISO != null) ? t.respByISO : t.resolveByISO;
  if (iso == null) return false;
  final ms = DateTime.parse(iso).millisecondsSinceEpoch - kNowList.millisecondsSinceEpoch;
  return ms < 3600000;
}

/// Board bucket state: breached / lt1h / today / ontrack, or null when the
/// ticket is not new/open. Uses the board anchor (09:41).
String? boardState(Ticket t) {
  if (t.status != 'new' && t.status != 'open') return null;
  final due = _dueMs(t);
  final now = kNowBoard.millisecondsSinceEpoch;
  if (due == null) return 'ontrack';
  if (due < now) return 'breached';
  if (due - now < 3600000) return 'lt1h';
  if (due <= kEod.millisecondsSinceEpoch) return 'today';
  return 'ontrack';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _clock(DateTime d) {
  var h = d.hour;
  final ap = h >= 12 ? 'PM' : 'AM';
  h = h % 12 == 0 ? 12 : h % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
}

/// The board row SLA pill (label + tones).
class BoardPill {
  final String label;
  final Color bg;
  final Color fg;
  const BoardPill(this.label, this.bg, this.fg);
}

BoardPill boardPill(Ticket t) {
  final due = _dueMs(t);
  final st = boardState(t);
  final now = kNowBoard.millisecondsSinceEpoch;
  // A ticket can have no deadline at all — the API returns a null
  // `sla_remaining_seconds` for those, and helpdesk.md §7 says they land in
  // `on_track` because they cannot breach. Every branch below dereferenced
  // `due!`, so such a row crashed the board rather than rendering.
  if (due == null) {
    return BoardPill('No due date', AppColors.bgChipGrey, AppColors.textLabelAlt);
  }
  if (st == 'breached') {
    final mins = (now - due) ~/ 60000;
    return BoardPill('Overdue ${mins ~/ 60}h ${mins % 60}m', AppColors.tintRed, AppColors.error);
  }
  if (st == 'lt1h') {
    final mins = ((due - now) / 60000).ceil();
    return BoardPill('Breach in ${mins < 1 ? 1 : mins}m', AppColors.tintAmber, AppColors.warningDeep);
  }
  final d = DateTime.fromMillisecondsSinceEpoch(due);
  if (st == 'today') {
    return BoardPill('Due ${_clock(d)}', AppColors.bgChipGrey, AppColors.textLabelAlt);
  }
  return BoardPill('Due ${d.day} ${_months[d.month - 1]}', AppColors.bgChipGrey, AppColors.textLabelAlt);
}

// ── Home dashboard SLA state ──

int _homeDue(Ticket t) {
  final respDue = (t.respByISO != null && t.responded == null) ? DateTime.parse(t.respByISO!).millisecondsSinceEpoch : 1 << 62;
  final resDue = t.resolveByISO != null ? DateTime.parse(t.resolveByISO!).millisecondsSinceEpoch : 1 << 62;
  return respDue < resDue ? respDue : resDue;
}

/// Home SLA state: within / risk / breached. Uses the board anchor (09:41).
String homeState(Ticket t) {
  final due = _homeDue(t);
  final now = kNowBoard.millisecondsSinceEpoch;
  if (due == 1 << 62) return 'within';
  if (due < now) return 'breached';
  if (due - now < 86400000) return 'risk';
  return 'within';
}

String homeOverLabel(Ticket t) {
  final now = kNowBoard.millisecondsSinceEpoch;
  final h = ((now - _homeDue(t)) ~/ 3600000);
  final hh = h < 1 ? 1 : h;
  return hh < 24 ? 'Overdue ${hh}h' : 'Overdue ${(hh / 24).round()}d';
}
