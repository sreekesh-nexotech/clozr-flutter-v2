import 'package:intl/intl.dart';

/// Date parsing and display formatting.
///
/// The presentation layer must never build a date string by hand — every
/// format the design uses is named here, so a change lands in one place.
///
/// These formats deliberately match the strings the mock data sources hard-code
/// today (`"16 Jun 2026"`, `"2h ago"`, `"09:30"`), so when the entities are
/// retyped to `DateTime` the rendered output stays identical.
class AppDateUtils {
  const AppDateUtils._();

  // ── Patterns ──

  /// `16 Jun 2026` — full date on detail screens and due dates.
  static final DateFormat fullDate = DateFormat('d MMM yyyy');

  /// `14 May` — compact date on cards.
  static final DateFormat shortDate = DateFormat('d MMM');

  /// `Thu, 9 Jul` — the CRM home header.
  static final DateFormat headerDate = DateFormat('EEE, d MMM');

  /// `09:30` — 24-hour clock.
  static final DateFormat timeOfDay = DateFormat('HH:mm');

  /// `16 Jun 2026, 09:30` — timestamped audit rows.
  static final DateFormat dateAndTime = DateFormat('d MMM yyyy, HH:mm');

  /// `Jun 2026` — month grouping headers.
  static final DateFormat monthAndYear = DateFormat('MMM yyyy');

  // ── Relative-time thresholds ──

  /// Below this many seconds a timestamp reads as "now".
  static const int justNowSeconds = 60;

  /// Days after which relative time gives way to an absolute date.
  static const int relativeCutoffDays = 7;

  /// Parses an ISO-8601 string, returning `null` when it is absent or invalid.
  ///
  /// Never throws — malformed server dates degrade to `null` rather than
  /// breaking a whole list.
  static DateTime? parseIso(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }

  /// Formats [date] as `16 Jun 2026`, or [fallback] when null.
  static String formatFullDate(DateTime? date, {String fallback = '—'}) =>
      date == null ? fallback : fullDate.format(date);

  /// Formats [date] as `14 May`, or [fallback] when null.
  static String formatShortDate(DateTime? date, {String fallback = '—'}) =>
      date == null ? fallback : shortDate.format(date);

  /// Formats [date] as `09:30`, or [fallback] when null.
  static String formatTime(DateTime? date, {String fallback = '—'}) =>
      date == null ? fallback : timeOfDay.format(date);

  /// Compact elapsed time: `now`, `7m`, `2h`, `1d`, `3w`.
  ///
  /// Pass [now] in tests to keep the result deterministic.
  static String relative(DateTime? date, {DateTime? now}) {
    if (date == null) return '—';
    final reference = now ?? DateTime.now();
    final elapsed = reference.difference(date);

    if (elapsed.inSeconds < justNowSeconds) return 'now';
    if (elapsed.inMinutes < Duration.minutesPerHour) return '${elapsed.inMinutes}m';
    if (elapsed.inHours < Duration.hoursPerDay) return '${elapsed.inHours}h';
    if (elapsed.inDays < DateTime.daysPerWeek) return '${elapsed.inDays}d';
    return '${elapsed.inDays ~/ DateTime.daysPerWeek}w';
  }

  /// Elapsed time with an `ago` suffix: `2h ago`, `1d ago`.
  static String relativeAgo(DateTime? date, {DateTime? now}) {
    if (date == null) return '—';
    final value = relative(date, now: now);
    return value == 'now' ? value : '$value ago';
  }

  /// Whether [date] falls on the same calendar day as [other].
  static bool isSameDay(DateTime? date, DateTime? other) {
    if (date == null || other == null) return false;
    return date.year == other.year &&
        date.month == other.month &&
        date.day == other.day;
  }

  /// Whether [date] is today, relative to [now].
  static bool isToday(DateTime? date, {DateTime? now}) =>
      isSameDay(date, now ?? DateTime.now());

  /// Whether [date] is strictly before the start of today — i.e. overdue.
  static bool isOverdue(DateTime? date, {DateTime? now}) {
    if (date == null) return false;
    final reference = now ?? DateTime.now();
    final startOfToday =
        DateTime(reference.year, reference.month, reference.day);
    return date.isBefore(startOfToday);
  }

  /// Day-bucket label used by the notifications feed.
  static String dayBucket(DateTime? date, {DateTime? now}) {
    if (date == null) return 'earlier';
    final reference = now ?? DateTime.now();
    if (isSameDay(date, reference)) return 'today';
    final yesterday = reference.subtract(const Duration(days: 1));
    if (isSameDay(date, yesterday)) return 'yesterday';
    return 'earlier';
  }
}
