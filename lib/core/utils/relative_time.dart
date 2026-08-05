import 'package:intl/intl.dart';

// Formatters are hoisted to module level — constructing a DateFormat parses the
// pattern and resolves locale symbols each time, and mappers call these
// per-row across large lists.
final DateFormat _dayMonth = DateFormat('d MMM');
final DateFormat _dayMonthYear = DateFormat('d MMM yyyy');

/// Formats server timestamps into the compact relative strings the cards use
/// ("Just now", "5m ago", "2h ago", "Yesterday", "3d ago", "9 Jul").
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
  return _dayMonth.format(local);
}

/// Parses an ISO-8601 timestamp defensively — the API emits both `Z`-suffixed
/// and offset forms; bad input returns null instead of throwing.
DateTime? parseApiDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// "9 Jul 2026"-style absolute date used on detail screens.
String absoluteDate(DateTime? time) =>
    time == null ? '' : _dayMonthYear.format(time.toLocal());
