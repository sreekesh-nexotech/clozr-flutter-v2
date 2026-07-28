import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/ticket.dart';

/// Pure SLA / breach computations ported from the prototype's helpdesk
/// view-models. Two fixed "now" anchors match the design exactly:
///  - [kNowList] (09:00) drives the tickets list card + detail banner.
///  - [kNowBoard] (09:41) drives the Support Overview board + home dashboard.
final DateTime kNowList = DateTime.parse('2026-07-09T09:00:00');
final DateTime kNowBoard = DateTime.parse('2026-07-09T09:41:00');
final DateTime kEod = DateTime.parse('2026-07-09T23:59:59');

/// Priority → pill colour (`PROJPRI`) used by the list/detail priority pill.
/// Urgent is not in the map, falling back to muted grey, matching the design.
Color ticketPriPillColor(String pri) => const {
      'High': AppColors.error,
      'Medium': AppColors.warningDeep,
      'Low': AppColors.success,
    }[pri] ??
    AppColors.textMuted;

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
  if (st == 'breached') {
    final mins = (now - due!) ~/ 60000;
    return BoardPill('Overdue ${mins ~/ 60}h ${mins % 60}m', AppColors.tintRed, AppColors.error);
  }
  if (st == 'lt1h') {
    final mins = ((due! - now) / 60000).ceil();
    return BoardPill('Breach in ${mins < 1 ? 1 : mins}m', AppColors.tintAmber, AppColors.warningDeep);
  }
  final d = DateTime.fromMillisecondsSinceEpoch(due!);
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
