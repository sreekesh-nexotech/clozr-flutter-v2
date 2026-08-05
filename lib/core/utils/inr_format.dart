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

  if (abs >= 10000000) return '$sign₹${trim(abs / 10000000)}Cr';
  if (abs >= 100000) return '$sign₹${trim(abs / 100000)}L';
  if (abs >= 1000) return '$sign₹${trim(abs / 1000)}K';
  return '$sign₹${_grouped.format(abs)}';
}

/// Parses API money values: JSON numbers or decimal strings ("450000.00").
double parseAmount(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String && value.isNotEmpty) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}
