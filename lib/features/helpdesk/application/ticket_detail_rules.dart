import '../../../core/network/app_error.dart';
import '../../../core/utils/relative_time.dart';
import '../domain/entities/ticket.dart';

/// The ticket detail's wording and gates, ported from the webapp's
/// `TicketDetailScreen`, `ticketInfoFields.tsx`, `ticketFormat.ts`,
/// `issueEnums.ts`, `issue.ts` and `issueError.ts`. Pure, so the copy is
/// unit-tested rather than eyeballed on a device.

/// "Phone" / "Email" / "WhatsApp" / "API / Webhook"; "Unset" when none.
String ticketChannelLabel(String? code) {
  final c = (code ?? '').trim().toLowerCase();
  if (c.isEmpty) return 'Unset';
  const known = {'email': 'Email', 'whatsapp': 'WhatsApp', 'phone': 'Phone', 'api': 'API / Webhook'};
  if (known[c] case final label?) return label;
  final words = c.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  return words[0].toUpperCase() + words.substring(1);
}

/// Only email and WhatsApp can dispatch a reply; phone / API / unset cannot.
bool isReplyDispatchable(String? code) => code == 'email' || code == 'whatsapp';

/// "Log first response" is offered while no first response is recorded and
/// the ticket is not locked — on any channel.
bool canLogFirstResponse(Ticket t) => (t.respondedISO ?? '').isEmpty && !t.isLocked;

/// Header sub-line: "<Category or Uncategorised> · <Customer or No customer>".
String ticketHeaderSubline(Ticket t) {
  final f = t.facts;
  final category = f != null ? (f.typeName ?? 'Uncategorised') : t.cat;
  final customer = f?.customerName ?? 'No customer';
  return '$category · $customer';
}

/// Header source line: "via <channel> · <time-ago>" — the raw channel key as
/// the webapp prints it ("unset" when none).
String ticketViaLine(Ticket t, {DateTime? now}) =>
    'via ${t.facts?.channelCode ?? 'unset'} · ${_timeAgo(t.createdISO, now: now)}';

String _timeAgo(String? iso, {DateTime? now}) {
  final then = DateTime.tryParse(iso ?? '');
  if (then == null) return '—';
  final secs = (now ?? DateTime.now()).difference(then).inSeconds;
  if (secs < 60) return 'Just now';
  if (secs < 3600) return '${secs ~/ 60}m ago';
  if (secs < 86400) return '${secs ~/ 3600}h ago';
  return '${secs ~/ 86400}d ago';
}

/// "First response 5m ago" beside the composer once one is recorded.
String firstResponseAgo(Ticket t, {DateTime? now}) =>
    'First response ${_timeAgo(t.respondedISO, now: now).toLowerCase()}';

/// "Added 5m ago · Sufail Salim".
String attachmentAddedLine(TicketAttachment a, {DateTime? now, String uploader = ''}) {
  final ago = _timeAgo(a.uploadedAt?.toIso8601String(), now: now);
  final by = a.uploadedBy.isNotEmpty ? a.uploadedBy : uploader;
  return by.isEmpty ? 'Added $ago' : 'Added $ago · $by';
}

/// The webapp's `formatDateTime` ("—" when unknown).
String ticketDateTime(String? iso) {
  final d = parseApiDate(iso);
  return d == null ? '—' : absoluteDateTime(d);
}

/// "1 hour", "8 hours", "1 day", "7 days"; "No SLA" without one.
String formatSlaTarget(num? value, String? unit) {
  final u = (unit ?? '').trim().toLowerCase();
  if (value == null || u.isEmpty) return 'No SLA';
  final singular = u.endsWith('s') ? u.substring(0, u.length - 1) : u;
  final v = value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  return '$v ${value == 1 ? singular : '${singular}s'}';
}

/// The webapp's `formatSlaRemaining`: "2d 3h left" / "Overdue 4h 12m".
({String label, bool overdue}) formatSlaRemaining(double seconds) {
  final overdue = seconds < 0;
  final abs = seconds.abs().floor();
  final d = abs ~/ 86400, h = (abs % 86400) ~/ 3600, m = (abs % 3600) ~/ 60;
  final label = d > 0 ? '${d}d ${h}h' : (h > 0 ? '${h}h ${m}m' : '${m}m');
  return (label: overdue ? 'Overdue $label' : '$label left', overdue: overdue);
}

/// How an SLA row reads: neutral, met (green), muted, at risk (amber) or
/// breached (red).
enum SlaTone { normal, met, muted, atRisk, breached }

enum SlaIcon { check, pause, clock, alert, off }

typedef SlaSeg = ({String label, SlaTone tone, SlaIcon icon});

/// The First response row; null when the ticket has no first-response
/// target, in which case the row is not shown at all.
SlaSeg? firstResponseSeg(Ticket t) {
  final f = t.facts;
  if ((t.respByISO ?? '').isEmpty) return null;
  if ((t.respondedISO ?? '').isNotEmpty) {
    return (label: 'Met · ${ticketDateTime(t.respondedISO)}', tone: SlaTone.met, icon: SlaIcon.check);
  }
  if (f?.statusOnHold ?? t.isPaused) return (label: 'Paused', tone: SlaTone.muted, icon: SlaIcon.pause);
  final left = f?.firstResponseRemainingSeconds;
  if (left == null) return (label: 'Due ${ticketDateTime(t.respByISO)}', tone: SlaTone.normal, icon: SlaIcon.clock);
  final r = formatSlaRemaining(left);
  return r.overdue
      ? (label: 'Breached · was due ${ticketDateTime(t.respByISO)}', tone: SlaTone.breached, icon: SlaIcon.alert)
      : (label: 'Due ${ticketDateTime(t.respByISO)} · ${r.label}', tone: SlaTone.normal, icon: SlaIcon.clock);
}

/// The Resolution row — always shown.
SlaSeg resolutionSeg(Ticket t) {
  if ((t.resolvedISO ?? '').isNotEmpty) {
    return (label: 'Resolved · ${ticketDateTime(t.resolvedISO)}', tone: SlaTone.met, icon: SlaIcon.check);
  }
  final left = t.facts?.slaRemainingSeconds;
  if (left == null) return (label: 'No SLA', tone: SlaTone.muted, icon: SlaIcon.off);
  if (t.facts?.slaHoldStarted ?? false) {
    return (label: 'Paused — waiting on customer', tone: SlaTone.muted, icon: SlaIcon.pause);
  }
  final r = formatSlaRemaining(left);
  if (r.overdue) {
    return (label: '${r.label} · was due ${ticketDateTime(t.resolveByISO)}', tone: SlaTone.breached, icon: SlaIcon.alert);
  }
  return (
    label: 'Due ${ticketDateTime(t.resolveByISO)} · ${r.label}',
    tone: left <= 86400 ? SlaTone.atRisk : SlaTone.normal,
    icon: SlaIcon.clock,
  );
}

/// "Billable · ₹2,500" / "Billable · product" / "Billed · …"; null when the
/// ticket is not billable (no Billing row).
String? billingRowValue(Ticket t, String Function(double) money) {
  if (!t.billable) return null;
  final parts = [t.isBilled ? 'Billed' : 'Billable'];
  final amount = double.tryParse(t.billableAmount ?? '');
  if (amount != null) parts.add(money(amount));
  if ((t.billableProductId ?? '').isNotEmpty) parts.add(amount != null ? '+ product' : 'product');
  return parts.join(' · ');
}

/// `form.order_id` → "Order id".
String customFieldLabel(String key) {
  final stripped = key.startsWith('form.') ? key.substring(5) : key;
  final words = stripped.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (words.isEmpty) return key;
  return words[0].toUpperCase() + words.substring(1);
}

/// A refused attach / detach in the picker's own words, keyed on the
/// server's `error_codes` (the prose names tickets and changes).
String hierarchyErrorCopy(AppError e) {
  final codes = e.fieldErrorCodes('parent_issue');
  if (codes.contains('parent_self_reference')) return "A ticket can't be its own parent.";
  if (codes.contains('parent_depth_exceeded')) {
    return 'That ticket is already a child of another ticket. Tickets can only nest two levels deep.';
  }
  if (codes.contains('parent_would_nest')) {
    return "That ticket already has children of its own, so it can't become a child.";
  }
  if (e.fieldErrors?.containsKey('issue_id') == true ||
      RegExp('not found in this organization', caseSensitive: false).hasMatch(e.bareMessage)) {
    return "That ticket couldn't be found in this workspace.";
  }
  return e.bareMessage;
}

/// The Assignee options: users who can be assigned Helpdesk tickets, with
/// the current assignee kept even when no longer eligible.
List<({String id, String name})> assigneeChoices(
  List<({String id, String name})> eligible, {
  String? currentId,
  String? currentName,
}) {
  final out = [...eligible];
  if (currentId != null && currentId.isNotEmpty && !out.any((u) => u.id == currentId)) {
    out.insert(0, (id: currentId, name: (currentName ?? '').isEmpty ? 'Current assignee' : currentName!));
  }
  return out;
}
