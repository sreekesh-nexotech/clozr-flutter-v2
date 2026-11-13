import 'package:intl/intl.dart';

// Hoisted so the grouping formatter isn't rebuilt per row during list mapping.
final NumberFormat _grouped = NumberFormat('#,##0');

/// Formats rupee amounts the way the design shows them: `₹18L`, `₹2.4Cr`,
/// `₹45K`, `₹950`. The API sends money as raw-rupee numbers or 2-dp strings —
/// [parseAmount] normalizes both.
String formatInr(num? amount) {
  if (amount == null) return '';
  final value = amount.toDouble();
  final abs = value.abs();
  final sign = value < 0 ? '-' : '';

  String trim(double v) {
    final rounded = (v * 10).roundToDouble() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toStringAsFixed(1);
  }

  // From a thousand crore the number would be a bare six-digit run
  // ("₹120000Cr"): group it the Indian way ("₹1,20,000Cr") so it stays legible.
  if (abs >= 10000000000) {
    return '$sign₹${NumberFormat.decimalPattern('en_IN').format((abs / 10000000).round())}Cr';
  }
  if (abs >= 10000000) return '$sign₹${trim(abs / 10000000)}Cr';
  if (abs >= 100000) return '$sign₹${trim(abs / 100000)}L';
  if (abs >= 1000) return '$sign₹${trim(abs / 1000)}K';
  return '$sign₹${_grouped.format(abs)}';
}

/// Full rupee amount with Indian digit grouping, as the webapp's list cells show
/// it: `₹3,01,785.69`, `₹1,000` (paise only when there are any).
String formatInrFull(num? amount) {
  if (amount == null) return '—';
  final v = amount.toDouble();
  final whole = (v * 100).roundToDouble() % 100 == 0;
  return NumberFormat.currency(
          locale: 'en_IN', symbol: '₹', decimalDigits: whole ? 0 : 2)
      .format(v);
}

/// Exact rupee amount, always with paise: `₹5,999.00`, `₹7,078.82` — product
/// and package prices, so the header, Pricing and lists show one value
/// (UI/UX audit #45).
String formatInrExact(num? amount) {
  if (amount == null) return '—';
  return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)
      .format(amount.toDouble());
}

/// Formats a line quantity for display: `1.0` reads "1", `2.5` reads "2.5".
///
/// Quantities became fractional with the accounting-readiness change and now
/// arrive as decimal strings ("1.000"), so they are carried as doubles. A bare
/// `toString()` would print "Qty 1.0" on every whole-number line.
String formatQty(double qty) {
  final text = qty.toStringAsFixed(3);
  final trimmed = text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
  return trimmed.isEmpty ? '0' : trimmed;
}

/// Parses API money values: JSON numbers or decimal strings ("450000.00").
double parseAmount(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String && value.isNotEmpty) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}
