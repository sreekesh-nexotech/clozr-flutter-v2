import '../../../../core/utils/money_format.dart';

/// Quotes › Win / loss report (`GET /quotations/quotations/win-loss-report/`).
///
/// Every figure here is the server's: win rate (won ÷ (won + lost + expired)),
/// averages and won value (before GST) arrive pre-computed as decimal strings
/// and are only formatted for display. Superseded revisions are excluded
/// server-side. Mirrors the webapp's `toWinLossReport` / `config/winLoss.ts`.

/// One set of report figures — the summary, or one breakdown row.
class WinLossMetrics {
  const WinLossMetrics({
    required this.total,
    required this.won,
    required this.lost,
    required this.expired,
    required this.open,
    required this.winRate,
    required this.avgDaysToAccept,
    required this.avgDiscountPct,
    required this.wonValue,
  });

  final int total;
  final int won;
  final int lost;
  final int expired;
  final int open;

  /// Decimal strings as sent; null = nothing to measure (shown as "—").
  final String? winRate;
  final String? avgDaysToAccept;
  final String? avgDiscountPct;

  /// Won value before GST; "0.00" when absent.
  final String wonValue;

  factory WinLossMetrics.fromJson(Map<String, dynamic> j) => WinLossMetrics(
        total: _int(j['total']),
        won: _int(j['won']),
        lost: _int(j['lost']),
        expired: _int(j['expired']),
        open: _int(j['open']),
        winRate: _decimalOrNull(j['win_rate']),
        avgDaysToAccept: _decimalOrNull(j['avg_days_to_accept']),
        avgDiscountPct: _decimalOrNull(j['avg_discount_pct']),
        wonValue: _decimalOrNull(j['won_value']) ?? '0.00',
      );
}

/// A breakdown row (owner / product / lead source). [name] is '' for the
/// "no owner / product / source" bucket — the screen labels it.
class WinLossGroupRow extends WinLossMetrics {
  const WinLossGroupRow({
    required this.key,
    required this.name,
    required super.total,
    required super.won,
    required super.lost,
    required super.expired,
    required super.open,
    required super.winRate,
    required super.avgDaysToAccept,
    required super.avgDiscountPct,
    required super.wonValue,
  });

  final String key;
  final String name;

  factory WinLossGroupRow._from(Map<String, dynamic> j, String idKey, String nameKey, int index) {
    final m = WinLossMetrics.fromJson(j);
    final id = '${j[idKey] ?? ''}';
    return WinLossGroupRow(
      key: id.isEmpty ? 'none-$index' : id,
      name: j[nameKey] is String ? j[nameKey] as String : '',
      total: m.total,
      won: m.won,
      lost: m.lost,
      expired: m.expired,
      open: m.open,
      winRate: m.winRate,
      avgDaysToAccept: m.avgDaysToAccept,
      avgDiscountPct: m.avgDiscountPct,
      wonValue: m.wonValue,
    );
  }
}

class WinLossReport {
  const WinLossReport({
    required this.dateFrom,
    required this.dateTo,
    required this.summary,
    required this.byOwner,
    required this.byProduct,
    required this.bySource,
  });

  /// The range the server applied; '' = open-ended.
  final String dateFrom;
  final String dateTo;
  final WinLossMetrics summary;
  final List<WinLossGroupRow> byOwner;
  final List<WinLossGroupRow> byProduct;
  final List<WinLossGroupRow> bySource;

  factory WinLossReport.fromJson(Object? body) {
    final j = body is Map ? Map<String, dynamic>.from(body) : const <String, dynamic>{};
    List<WinLossGroupRow> rows(String field, String idKey, String nameKey) {
      final raw = j[field];
      if (raw is! List) return const [];
      final maps = [for (final r in raw) if (r is Map) Map<String, dynamic>.from(r)];
      return [for (var i = 0; i < maps.length; i++) WinLossGroupRow._from(maps[i], idKey, nameKey, i)];
    }

    final summary = j['summary'];
    return WinLossReport(
      dateFrom: j['date_from'] is String ? j['date_from'] as String : '',
      dateTo: j['date_to'] is String ? j['date_to'] as String : '',
      summary: WinLossMetrics.fromJson(summary is Map ? Map<String, dynamic>.from(summary) : const {}),
      byOwner: rows('by_owner', 'owner_id', 'owner_name'),
      byProduct: rows('by_product', 'product_id', 'product_name'),
      bySource: rows('by_source', 'source_id', 'source_name'),
    );
  }
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String? _decimalOrNull(Object? v) {
  if (v == null || v == '') return null;
  return '$v';
}

// ─── date range ──────────────────────────────────────────────────────────────

/// Quick ranges on the quote's creation date. [custom] = the user typed a date.
enum WinLossPreset {
  last30('Last 30 days'),
  last90('Last 90 days'),
  thisYear('This year'),
  allTime('All time'),
  custom('Custom');

  const WinLossPreset(this.label);
  final String label;

  /// The tappable presets, in the webapp's order.
  static const quick = [last30, last90, thisYear, allTime];
}

/// `(from, to)` ISO days for [preset] relative to [today]; '' = open-ended.
({String from, String to}) winLossPresetRange(WinLossPreset preset, DateTime today) {
  final to = isoDay(today);
  switch (preset) {
    case WinLossPreset.allTime:
    case WinLossPreset.custom:
      return (from: '', to: '');
    case WinLossPreset.thisYear:
      return (from: '${today.year.toString().padLeft(4, '0')}-01-01', to: to);
    case WinLossPreset.last30:
      return (from: isoDay(DateTime(today.year, today.month, today.day - 29)), to: to);
    case WinLossPreset.last90:
      return (from: isoDay(DateTime(today.year, today.month, today.day - 89)), to: to);
  }
}

final RegExp _isoDay = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Whether [s] is a real calendar day in `YYYY-MM-DD` form.
bool isValidIsoDay(String s) {
  if (!_isoDay.hasMatch(s)) return false;
  final d = DateTime.tryParse(s);
  return d != null && isoDay(d) == s;
}

/// A range the server accepts (it answers 400 otherwise), or the error to show.
/// Blank = open-ended and always fine.
String? winLossRangeError(String from, String to) {
  if ((from.isNotEmpty && !isValidIsoDay(from)) || (to.isNotEmpty && !isValidIsoDay(to))) {
    return 'Use a valid date.';
  }
  if (from.isNotEmpty && to.isNotEmpty && from.compareTo(to) > 0) {
    return 'The start date must be on or before the end date.';
  }
  return null;
}

/// Query params for the request — only the non-blank bounds.
Map<String, dynamic> winLossQuery(String from, String to) => {
      if (from.isNotEmpty) 'date_from': from,
      if (to.isNotEmpty) 'date_to': to,
    };

// ─── labels ──────────────────────────────────────────────────────────────────

String _trimmed(double n, int dp) {
  var s = n.toStringAsFixed(dp);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s == '-0' ? '0' : s;
}

/// "62.50" → "62.5%"; null (nothing closed) → "—".
String winRateLabel(String? value) {
  if (value == null) return '—';
  final n = double.tryParse(value);
  return n == null || !n.isFinite ? '—' : '${_trimmed(n, 1)}%';
}

/// "3.50" → "3.5 days", "1.00" → "1 day"; null → "—".
String daysLabel(String? value) {
  if (value == null) return '—';
  final n = double.tryParse(value);
  if (n == null || !n.isFinite) return '—';
  final r = _trimmed(n, 1);
  return '$r ${r == '1' ? 'day' : 'days'}';
}

/// "12.50" → "12.5%" (two decimals max); null / blank → "—".
String discountLabel(String? value) {
  if (value == null || value.isEmpty) return '—';
  final n = double.tryParse(value);
  return n == null || !n.isFinite ? '$value%' : '${_trimmed(n, 2)}%';
}
