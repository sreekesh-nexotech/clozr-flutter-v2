import 'dart:math';

import 'package:intl/intl.dart';

import 'inr_format.dart';

/// Money for the accounting screens.
///
/// The accounting API sends every amount as a two-decimal **string**
/// (`"1250.00"`) and expects strings back (handover §1). Ledger figures carry
/// paise, so nothing here rounds to whole rupees — [formatInr] does, and is
/// only fit for a KPI tile ([formatMoneyCompact] wraps it for that one use).

// Hoisted: rebuilt per row otherwise. `en_IN` gives lakh grouping
// (₹1,25,000.00), which is how the accountants reading these figures think.
final NumberFormat _inr =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Parses an API money string (or number) to a double — for sorting and for
/// client-side *hints* only, never for a figure sent back to the server.
double moneyNum(Object? value) => parseAmount(value);

/// `"125000.5"` → `₹1,25,000.50`. Null / blank → an em dash, so a missing
/// figure never reads as zero.
String formatMoneyStr(Object? value) {
  if (value == null || (value is String && value.trim().isEmpty)) return '—';
  return _inr.format(moneyNum(value));
}

/// `₹1.3L` — KPI tiles only, where space matters more than paise.
String formatMoneyCompact(Object? value) {
  if (value == null || (value is String && value.trim().isEmpty)) return '—';
  return formatInr(moneyNum(value));
}

/// A double back to the API's two-decimal string.
String toMoneyStr(double value) => value.toStringAsFixed(2);

/// Normalises what a user typed into a money box (`"1,250.5"`) to the API's
/// string form (`"1250.50"`), or null when it is not a number at all.
String? moneyInput(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return null;
  final v = double.tryParse(cleaned);
  if (v == null) return null;
  return toMoneyStr(v);
}

/// Whether an API money string is non-zero.
bool moneyIsZero(Object? value) => moneyNum(value).abs() < 0.005;

/// `YYYY-MM-DD` — the only date form the accounting API reads (in IST).
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `2026-09-24` → `24 Sep 2026`. Anything unparseable is shown as sent.
String formatApiDay(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat('d MMM yyyy').format(d);
}

final Random _rng = Random.secure();

/// A random (v4) UUID — the `event_id` idempotency key a posting form sends
/// (handover §5). Generated once when the form opens and reused for every
/// retry of that submission, so a double tap or a timeout replay posts once.
String newEventId() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
