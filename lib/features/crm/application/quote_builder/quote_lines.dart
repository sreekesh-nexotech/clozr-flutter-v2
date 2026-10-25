import 'package:intl/intl.dart';

/// Pure line-item logic for the quote builder — a port of the webapp's
/// `builder/quoteLines.ts` + `domain/entities/quoteCharge.ts`, so a line is
/// validated, priced and sent exactly the way the web builder does it.
///
/// The rules that matter most:
/// * an **untouched catalog line omits `unit_price`** — the server prices it
///   from the catalog in the quote's tax mode ("catalog price");
/// * typing a price **pins** it (`priceTouched`); the rotate button un-pins;
/// * a line is never dropped silently — [lineProblem] names what to fix and
///   the builder blocks the save until it is fixed;
/// * the client never computes tax: every figure comes from `preview-tax`.

// ── Recurring charges (D-3(b)) ────────────────────────────────────────────

/// `one_time` / `recurring`.
enum ChargeType { oneTime, recurring }

/// The API's billing periods, in the order the web picker lists them.
const billingPeriods = <String>['month', 'quarter', 'half_year', 'year', 'custom_days'];

/// Picker labels, verbatim from the web `LineChargeControl`.
const billingPeriodLabels = <String, String>{
  'month': 'every month',
  'quarter': 'every quarter',
  'half_year': 'every half-year',
  'year': 'every year',
  'custom_days': 'every N days',
};

/// A line's (or a product's) charge. One-time charges carry no period.
class LineCharge {
  const LineCharge({
    required this.chargeType,
    this.billingPeriod,
    this.billingPeriodDays,
    this.termPeriods,
  });

  static const oneTime = LineCharge(chargeType: ChargeType.oneTime);

  final ChargeType chargeType;
  final String? billingPeriod;

  /// Days per period, only for `custom_days`.
  final int? billingPeriodDays;

  /// Number of periods; null = until cancelled.
  final int? termPeriods;

  bool get isRecurring => chargeType == ChargeType.recurring;

  LineCharge copyWith({
    String? billingPeriod,
    Object? billingPeriodDays = _unset,
    Object? termPeriods = _unset,
  }) =>
      LineCharge(
        chargeType: chargeType,
        billingPeriod: billingPeriod ?? this.billingPeriod,
        billingPeriodDays: billingPeriodDays == _unset ? this.billingPeriodDays : billingPeriodDays as int?,
        termPeriods: termPeriods == _unset ? this.termPeriods : termPeriods as int?,
      );

  /// Reads the charge keys off a line / product / preview row.
  static LineCharge fromRow(Map<String, dynamic>? row) {
    if (row == null || row['charge_type'] != 'recurring') return oneTime;
    final raw = row['billing_period'];
    final period = billingPeriods.contains(raw) ? raw as String : null;
    return LineCharge(
      chargeType: ChargeType.recurring,
      billingPeriod: period,
      billingPeriodDays: period == 'custom_days' ? _intOrNull(row['billing_period_days']) : null,
      termPeriods: _intOrNull(row['term_periods']),
    );
  }

  /// The write keys of a quote line (one-time sends no period).
  Map<String, dynamic> toWrite() => isRecurring
      ? {
          'charge_type': 'recurring',
          'billing_period': billingPeriod,
          'billing_period_days': billingPeriod == 'custom_days' ? billingPeriodDays : null,
          'term_periods': termPeriods,
        }
      : {
          'charge_type': 'one_time',
          'billing_period': null,
          'billing_period_days': null,
          'term_periods': null,
        };
}

const Object _unset = Object();

int? _intOrNull(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Why a charge cannot be sent yet (null = fine) — the server refuses the same.
String? chargeProblem(LineCharge? charge) {
  if (charge == null || !charge.isRecurring) return null;
  if (charge.billingPeriod == null) return 'Choose how often it is billed.';
  if (charge.billingPeriod == 'custom_days') {
    final d = charge.billingPeriodDays;
    if (d == null || d < 1 || d > 366) return 'A custom period is 1 to 366 days.';
  }
  final t = charge.termPeriods;
  if (t != null && (t < 1 || t > 120)) {
    return 'The term is 1 to 120 periods (blank = until cancelled).';
  }
  return null;
}

/// "month", "half-year", "45 days".
String periodLabel(String? period, int? days) {
  switch (period) {
    case null:
      return '';
    case 'custom_days':
      return days == 1 ? 'day' : '${days ?? 0} days';
    case 'half_year':
      return 'half-year';
    default:
      return period;
  }
}

/// "× 12" or "until cancelled".
String termLabel(int? term) => term != null && term > 0 ? '× $term' : 'until cancelled';

/// "Every month × 12" / "Every quarter, until cancelled" / "One-time".
String chargeLabel(LineCharge? charge) {
  if (charge == null || !charge.isRecurring) return 'One-time';
  final every = 'Every ${periodLabel(charge.billingPeriod, charge.billingPeriodDays)}';
  return charge.termPeriods != null ? '$every × ${charge.termPeriods}' : '$every, until cancelled';
}

// ── The form row ──────────────────────────────────────────────────────────

/// `catalog` = picked from the product catalog; `free` = typed description.
enum LineKind { catalog, free }

int _lineSeq = 0;
String _nextLineKey() => 'line-${++_lineSeq}';

/// One draft line in the builder. Immutable; the screen swaps rows.
class QuoteFormItem {
  const QuoteFormItem({
    required this.key,
    required this.kind,
    this.productId = '',
    this.name = '',
    this.qty = '1',
    this.rate = '',
    this.priceTouched = false,
    this.isPackage = false,
    this.lineDiscount = '',
    this.charge,
    this.hsnSac = '',
    this.gstRate = '',
  });

  /// A fresh row. Quantity defaults to 1 — a blank quantity used to send no
  /// line at all.
  factory QuoteFormItem.blank([LineKind kind = LineKind.catalog]) =>
      QuoteFormItem(key: _nextLineKey(), kind: kind);

  /// Stable client key (widget key + preview correlation); never sent.
  final String key;
  final LineKind kind;
  final String productId;
  final String name;
  final String qty;

  /// Unit price as an exact decimal string ('' = not set). Never rounded.
  final String rate;

  /// The unit price is fixed on this line (typed, kept by a "Keep prices"
  /// flip, or a saved line's stored price).
  final bool priceTouched;

  /// A package is priced from the catalog and exploded by the server on save.
  final bool isPackage;

  /// A saved line's `line_discount` (exact decimal string); '' when none.
  final String lineDiscount;

  /// The line's charge when set here; null = the product's own (server).
  final LineCharge? charge;

  /// A free-text line's HSN/SAC and GST rate (a catalog line's come from its
  /// product).
  final String hsnSac;
  final String gstRate;

  QuoteFormItem copyWith({
    String? productId,
    String? name,
    String? qty,
    String? rate,
    bool? priceTouched,
    bool? isPackage,
    String? lineDiscount,
    Object? charge = _unset,
    String? hsnSac,
    String? gstRate,
  }) =>
      QuoteFormItem(
        key: key,
        kind: kind,
        productId: productId ?? this.productId,
        name: name ?? this.name,
        qty: qty ?? this.qty,
        rate: rate ?? this.rate,
        priceTouched: priceTouched ?? this.priceTouched,
        isPackage: isPackage ?? this.isPackage,
        lineDiscount: lineDiscount ?? this.lineDiscount,
        charge: charge == _unset ? this.charge : charge as LineCharge?,
        hsnSac: hsnSac ?? this.hsnSac,
        gstRate: gstRate ?? this.gstRate,
      );

  /// The row after a product is picked: priced by the server from the
  /// catalog, its own charge snapshotted by the server.
  QuoteFormItem withProduct(String id, {required String productName, required bool package}) => QuoteFormItem(
        key: key,
        kind: kind,
        productId: id,
        name: productName,
        qty: qty,
        isPackage: package,
      );

  /// "Use the catalog price" — un-pins the typed price.
  QuoteFormItem withCatalogPrice() => copyWith(rate: '', priceTouched: false, lineDiscount: '');
}

/// The server's sane upper bounds (`quote_rules.py`).
const quantityMax = 10000000;
const unitPriceMax = 1000000000;

final _unitPricePattern = RegExp(r'^\d+(\.\d{1,6})?$');
final _hsnSacPattern = RegExp(r'^\d{4,8}$');
final _gstRatePattern = RegExp(r'^\d{1,3}(\.\d{1,4})?$');

/// Clamps a quantity to the server's 3 decimal places (unparsable → 0).
double toQty(String raw) {
  final n = double.tryParse(raw.trim());
  if (n == null || !n.isFinite) return 0;
  return (n * 1000).roundToDouble() / 1000;
}

/// A typed price, cleaned of grouping commas / spaces / ₹.
String cleanUnitPrice(String raw) => raw.replaceAll(RegExp(r'[,\s₹]'), '');

bool isValidUnitPrice(String raw) => _unitPricePattern.hasMatch(cleanUnitPrice(raw));

bool _isNamed(QuoteFormItem it) =>
    it.kind == LineKind.catalog ? it.productId.isNotEmpty : it.name.trim().isNotEmpty;

/// Whether the line's own unit price is sent (vs. priced by the server).
bool sendsOwnPrice(QuoteFormItem it) {
  if (it.isPackage) return false;
  return it.kind == LineKind.free || it.priceTouched;
}

enum LineProblem { qty, price, charge, description, tax }

/// The GST slabs a typed line offers on a tenant without the rate master.
const gstRateSlabs = <String>['0', '0.25', '3', '5', '12', '18', '28'];

/// The slabs, plus the line's own rate when it is another one.
List<String> gstRateOptions(String current) {
  final rate = current.trim();
  final n = double.tryParse(rate);
  if (rate.isEmpty || gstRateSlabs.any((s) => double.parse(s) == n)) return [...gstRateSlabs];
  return [...gstRateSlabs, rate]..sort((a, b) => (double.tryParse(a) ?? 0).compareTo(double.tryParse(b) ?? 0));
}

/// A free-text line's HSN/SAC or GST rate the server would refuse.
enum FreeTaxProblem { hsn, rate }

FreeTaxProblem? freeLineTaxProblem(QuoteFormItem it) {
  final hsn = it.hsnSac.trim();
  if (hsn.isNotEmpty && !_hsnSacPattern.hasMatch(hsn)) return FreeTaxProblem.hsn;
  final rate = it.gstRate.trim();
  if (rate.isNotEmpty && (!_gstRatePattern.hasMatch(rate) || double.parse(rate) > 100)) {
    return FreeTaxProblem.rate;
  }
  return null;
}

/// Why a line cannot be sent yet, or null — in the web builder's priority.
LineProblem? lineProblem(QuoteFormItem it) {
  if (!_isNamed(it)) {
    return it.kind == LineKind.free && cleanUnitPrice(it.rate).isNotEmpty ? LineProblem.description : null;
  }
  final qty = toQty(it.qty);
  if (qty <= 0 || qty > quantityMax) return LineProblem.qty;
  if (sendsOwnPrice(it) &&
      (!isValidUnitPrice(it.rate) || double.parse(cleanUnitPrice(it.rate)) > unitPriceMax)) {
    return LineProblem.price;
  }
  if (chargeProblem(it.charge) != null) return LineProblem.charge;
  if (it.productId.isEmpty && freeLineTaxProblem(it) != null) return LineProblem.tax;
  return null;
}

/// The lines that go to the server (named, complete).
List<QuoteFormItem> includedLines(List<QuoteFormItem> items) =>
    [for (final it in items) if (_isNamed(it) && lineProblem(it) == null) it];

/// `2` → "2", `2.5` → "2.5", `0.125` → "0.125" (≤ 3 dp, like the web).
String qtyString(double qty) {
  var s = ((qty * 1000).roundToDouble() / 1000).toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s.isEmpty ? '0' : s;
}

/// Form rows → the `line_items` wire rows of a write or a tax preview (one
/// mapper, so a preview prices exactly what a save would store).
List<Map<String, dynamic>> toLineRows(List<QuoteFormItem> items) => [
      for (final it in includedLines(items))
        {
          'description': it.name.trim(),
          'quantity': qtyString(toQty(it.qty)),
          if (sendsOwnPrice(it)) 'unit_price': cleanUnitPrice(it.rate),
          if (it.productId.isNotEmpty) 'product_id': it.productId,
          if (it.lineDiscount.isNotEmpty && (double.tryParse(it.lineDiscount) ?? 0) > 0)
            'line_discount': it.lineDiscount,
          if (it.productId.isEmpty && it.hsnSac.trim().isNotEmpty) 'hsn_sac': it.hsnSac.trim(),
          if (it.productId.isEmpty && it.gstRate.trim().isNotEmpty) 'rate_pct': it.gstRate.trim(),
          if (it.charge != null) ...it.charge!.toWrite(),
        },
    ];

/// Trims a server decimal for an input without changing its value:
/// "1000.000000" → "1000", "999.500000" → "999.50", "846.610169" stays.
String formatUnitPriceInput(String exact) {
  final value = exact.trim();
  if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) return value;
  final parts = value.split('.');
  final whole = parts[0];
  final trimmed = parts.length > 1 ? parts[1].replaceFirst(RegExp(r'0+$'), '') : '';
  if (trimmed.isEmpty) return whole;
  return '$whole.${trimmed.length == 1 ? '${trimmed}0' : trimmed}';
}

/// A unit price at 2 dp unless the extra decimals change the line amount.
/// Display only — the exact string is what is stored and sent.
String displayUnitPrice(String exact, double qty) {
  final value = double.tryParse(cleanUnitPrice(exact));
  if (exact.isEmpty || value == null) return exact;
  final atTwo = (value * 100).roundToDouble() / 100;
  final q = qty > 0 ? qty : 1;
  if ((value * q * 100).round() == (atTwo * q * 100).round()) return atTwo.toStringAsFixed(2);
  return formatUnitPriceInput(cleanUnitPrice(exact));
}

final _groupedPrice = NumberFormat('#,##,##0.00####', 'en_IN');

/// "14160.00" → "14,160.00" (Indian grouping, 2–6 decimals).
String groupedUnitPrice(String display) {
  final n = double.tryParse(display);
  return display.isNotEmpty && n != null ? _groupedPrice.format(n) : display;
}

/// A saved quote's lines as form rows. Every saved line keeps its stored
/// price (touched), so a re-save never re-prices it from today's catalog.
List<QuoteFormItem> itemsFromSavedLines(List<Map<String, dynamic>> lines) {
  final sorted = [...lines]..sort((a, b) => (_intOrNull(a['line_no']) ?? 0).compareTo(_intOrNull(b['line_no']) ?? 0));
  return [
    for (final l in sorted)
      () {
        final productId = _str(l['product']).isNotEmpty ? _str(l['product']) : _str(l['product_id']);
        final discount = _str(l['line_discount']);
        final rate = l['rate_pct'];
        return QuoteFormItem(
          key: _nextLineKey(),
          kind: productId.isNotEmpty ? LineKind.catalog : LineKind.free,
          productId: productId,
          name: _str(l['description']),
          qty: qtyString(double.tryParse(_str(l['quantity'])) ?? 0),
          rate: formatUnitPriceInput(_str(l['unit_price'])),
          priceTouched: true,
          lineDiscount: (double.tryParse(discount) ?? 0) > 0 ? discount : '',
          charge: l.containsKey('charge_type') ? LineCharge.fromRow(l) : null,
          hsnSac: productId.isNotEmpty ? '' : _str(l['hsn_sac']),
          gstRate: productId.isNotEmpty || rate == null ? '' : formatRate(_str(rate)),
        );
      }(),
  ];
}

String _str(Object? v) => v == null ? '' : (v is String ? v : v.toString());

/// "18.0000" → "18", "0.2500" → "0.25".
String formatRate(String raw) {
  final n = double.tryParse(raw);
  if (n == null) return raw;
  var s = n.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  if (s.isEmpty) s = '0';
  return s;
}

// ── Server-priced lines (preview-tax) ─────────────────────────────────────

/// One priced line from `preview-tax` (or a saved quote's line).
class PricedLine {
  const PricedLine({
    required this.unitPrice,
    required this.totalPrice,
    this.sourcePackageId = '',
    this.lineDiscount = '',
    this.hsnSac = '',
    this.ratePct,
    this.cessPct,
    this.charge = LineCharge.oneTime,
  });

  factory PricedLine.fromJson(Map<String, dynamic> j) => PricedLine(
        unitPrice: _str(j['unit_price']),
        totalPrice: _str(j['total_price']),
        sourcePackageId: _str(j['source_package_id'] ?? j['source_package']),
        lineDiscount: _str(j['line_discount']),
        hsnSac: _str(j['hsn_sac']),
        ratePct: j['rate_pct'] == null ? null : _str(j['rate_pct']),
        cessPct: j['cess_pct'] == null ? null : _str(j['cess_pct']),
        charge: LineCharge.fromRow(j),
      );

  final String unitPrice;
  final String totalPrice;
  final String sourcePackageId;
  final String lineDiscount;
  final String hsnSac;
  final String? ratePct;
  final String? cessPct;
  final LineCharge charge;
}

/// A previewed form row: its key, and the package id when it is a package.
class PreviewRowRef {
  const PreviewRowRef(this.key, this.packageId);
  final String key;
  final String packageId;
}

List<PreviewRowRef> previewRowRefs(List<QuoteFormItem> items) =>
    [for (final it in items) PreviewRowRef(it.key, it.isPackage ? it.productId : '')];

/// Maps the server's priced lines back onto the rows that produced them, in
/// order. A package row owns every consecutive line exploded from it.
Map<String, List<PricedLine>> mapPreviewLines(List<PreviewRowRef> rows, List<PricedLine> lines) {
  final out = <String, List<PricedLine>>{};
  var at = 0;
  for (final row in rows) {
    final own = <PricedLine>[];
    if (row.packageId.isNotEmpty) {
      while (at < lines.length && lines[at].sourcePackageId == row.packageId) {
        own.add(lines[at++]);
      }
    } else if (at < lines.length) {
      own.add(lines[at++]);
    }
    out[row.key] = own;
  }
  return out;
}

/// A saved quote's own figures keyed by the rows built from it (same order) —
/// what a read-only quote shows instead of a live preview.
Map<String, List<PricedLine>> savedLinePricing(List<QuoteFormItem> items, List<Map<String, dynamic>> lines) {
  final saved = [...lines]..sort((a, b) => (_intOrNull(a['line_no']) ?? 0).compareTo(_intOrNull(b['line_no']) ?? 0));
  return {
    for (var i = 0; i < items.length && i < saved.length; i++) items[i].key: [PricedLine.fromJson(saved[i])],
  };
}

/// Applies a confirmed "Amounts are" flip to the rows, from the server's
/// preview of the flip (convert: take the converted price; keep: pin the
/// number shown). Packages are left alone.
List<QuoteFormItem> applyPriceFlip(
  List<QuoteFormItem> items,
  Map<String, List<PricedLine>> priced,
  String choice,
) =>
    [
      for (final it in items)
        () {
          if (it.isPackage) return it;
          final lines = priced[it.key];
          if (lines == null || lines.isEmpty) return it;
          if (it.kind == LineKind.catalog && !it.priceTouched && choice == 'convert') return it;
          return it.copyWith(
            rate: formatUnitPriceInput(lines.first.unitPrice),
            priceTouched: true,
            lineDiscount: it.lineDiscount.isNotEmpty ? lines.first.lineDiscount : it.lineDiscount,
          );
        }(),
    ];

/// Whether flipping the tax mode needs the Convert / Keep choice.
bool flipNeedsChoice(List<QuoteFormItem> items) => includedLines(items).any((it) => !it.isPackage);

/// The charge a line bills as: its own, else what the server snapshots.
LineCharge effectiveCharge(QuoteFormItem it, List<PricedLine>? lines) =>
    it.charge ?? (lines != null && lines.isNotEmpty ? lines.first.charge : LineCharge.oneTime);

/// Today as a local `YYYY-MM-DD`.
String localIsoDate([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
