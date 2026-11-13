import 'package:intl/intl.dart';

// Formatters are hoisted to module level — constructing a DateFormat parses the
// pattern and resolves locale symbols each time, and mappers call these
// per-row across large lists.
//
// One canonical style across the app, as the webapp (parity C17): dates
// `DD/MM/YYYY` (08/12/2025), date-times `DD/MM/YYYY, HH:mm` (24-hour).
final DateFormat _dayMonthYear = DateFormat('dd/MM/yyyy');
final DateFormat _dayMonthYearTime = DateFormat('dd/MM/yyyy, HH:mm');
final DateFormat _clock = DateFormat('HH:mm');

/// `DD/MM/YYYY` of a calendar day (no zone shift — for date-only values).
String fmtDay(DateTime d) => _dayMonthYear.format(d);

/// `HH:mm` (24-hour) of an instant, in the device's zone.
String fmtClock(DateTime time) => _clock.format(time.toLocal());

/// `HH:mm` from hour / minute fields (a picked time of day).
String fmtHm(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

const _monthIndex = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Reads a date the app (or an older build) displayed: `08/12/2025`,
/// `8 Dec 2025`, `08-Dec-2025` — anything after a `,` or `·` is ignored.
/// Null when it is none of those.
DateTime? parseDisplayDate(String s) {
  final head = s.split(RegExp(r'[,·]')).first.trim();
  var m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(head);
  if (m != null) {
    return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }
  m = RegExp(r'^(\d{1,2})[\s-]([A-Za-z]{3})[A-Za-z]*[\s-](\d{4})$')
      .firstMatch(head);
  if (m != null) {
    final mon = _monthIndex[m[2]!.toLowerCase()];
    if (mon != null) {
      return DateTime(int.parse(m[3]!), mon, int.parse(m[1]!));
    }
  }
  return null;
}

/// Formats server timestamps into the compact relative strings the cards use
/// ("Just now", "5m ago", "2h ago", "Yesterday", "3d ago", then the date —
/// `DD/MM/YYYY`, as the web).
String relativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final ref = now ?? DateTime.now();
  final local = time.toLocal();
  final diff = ref.difference(local);

  // A server clock slightly ahead of the device yields a negative diff — clamp
  // to "Just now" rather than rendering "-1d ago".
  if (diff.isNegative || diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';

  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days <= 1) return 'Yesterday';
  if (days < 7) return '${days}d ago';
  return _dayMonthYear.format(local);
}

/// Parses an ISO-8601 timestamp defensively — the API emits both `Z`-suffixed
/// and offset forms; bad input returns null instead of throwing.
DateTime? parseApiDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// `09/07/2026` — the absolute date used on detail screens.
String absoluteDate(DateTime? time) =>
    time == null ? '' : _dayMonthYear.format(time.toLocal());

/// `26/10/2026, 16:20` — date and time, for detail rows and audit entries
/// where the moment matters (the webapp's `formatDateTime`).
String absoluteDateTime(DateTime? time) =>
    time == null ? '' : _dayMonthYearTime.format(time.toLocal());
