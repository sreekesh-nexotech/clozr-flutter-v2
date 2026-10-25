import 'dart:convert';

import 'quote_lines.dart';

/// The quote's GST estimate as the server computes it (`tax_summary`,
/// `POST quotations/preview-tax/`, `charge_summary`) and how the builder asks
/// for it — a port of the webapp's `quoteTax.response.ts` + `priceFlip.ts`.
///
/// Money stays the decimal **string** the API sent; nothing here derives a tax
/// head. The builder only displays these figures.

String _dec(Object? v) => v == null ? '' : (v is String ? v : v.toString());
double _num(String v) => double.tryParse(v) ?? 0;

/// `tax_summary` — Sub-total, the GST heads, round off, grand total.
class TaxSummary {
  const TaxSummary({
    required this.isEstimate,
    required this.supply,
    required this.taxableTotal,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.cess,
    required this.roundOff,
    required this.grandTotal,
    this.warnings = const [],
  });

  static TaxSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final supply = j['supply'];
    return TaxSummary(
      // Quotes are always an estimate; only an explicit `false` drops it.
      isEstimate: j['is_estimate'] != false,
      supply: supply == 'INTRA' || supply == 'INTER' ? supply as String : null,
      taxableTotal: _dec(j['taxable_total']),
      cgst: _dec(j['cgst']),
      sgst: _dec(j['sgst']),
      igst: _dec(j['igst']),
      cess: _dec(j['cess']),
      roundOff: _dec(j['round_off']),
      grandTotal: _dec(j['grand_total']),
      warnings: [
        for (final w in (j['warnings'] is List ? j['warnings'] as List : const []))
          if (w is Map && _dec(w['message']).isNotEmpty) _dec(w['message']),
      ],
    );
  }

  final bool isEstimate;

  /// `INTRA` / `INTER` / null (unknown — show whichever heads are filled).
  final String? supply;
  final String taxableTotal;
  final String cgst;
  final String sgst;
  final String igst;
  final String cess;
  final String roundOff;
  final String grandTotal;
  final List<String> warnings;
}

/// One row of the totals panel.
class TotalsRow {
  const TotalsRow(this.label, this.value, {this.isTax = false});
  final String label;
  final String value;
  final bool isTax;
}

/// The web `TaxTotalsPanel` rows: Sub-total → CGST + SGST (intra) or IGST
/// (inter), each only when non-zero → Cess → Round off. Grand total is drawn
/// separately.
List<TotalsRow> taxTotalsRows(TaxSummary? s, {String? taxableFallback}) {
  final heads = <TotalsRow>[
    if (s?.supply != 'INTER') ...[
      TotalsRow('CGST', s?.cgst ?? '', isTax: true),
      TotalsRow('SGST', s?.sgst ?? '', isTax: true),
    ],
    if (s?.supply != 'INTRA') TotalsRow('IGST', s?.igst ?? '', isTax: true),
    TotalsRow('Cess', s?.cess ?? '', isTax: true),
  ];
  return [
    TotalsRow('Sub-total', s?.taxableTotal ?? taxableFallback ?? ''),
    for (final h in heads)
      if (_num(h.value) != 0) h,
    if (_num(s?.roundOff ?? '') != 0) TotalsRow('Round off', s!.roundOff),
  ];
}

/// One part of the recurring split.
class ChargePart {
  const ChargePart({required this.grandTotal, required this.lineCount});
  final String grandTotal;
  final int lineCount;
}

/// `charge_summary` — null on a quote without recurring lines.
class ChargeSummary {
  const ChargeSummary({
    required this.oneTime,
    required this.recurringGrandTotal,
    required this.periodLabel,
    required this.termPeriods,
  });

  static ChargeSummary? fromJson(Object? raw) {
    if (raw is! Map || raw['recurring'] is! Map) return null;
    final one = raw['one_time'] is Map ? raw['one_time'] as Map : const {};
    final rec = raw['recurring'] as Map;
    String total(Object? v) => _dec(v).isEmpty ? '0.00' : _dec(v);
    return ChargeSummary(
      oneTime: ChargePart(
        grandTotal: total(one['grand_total']),
        lineCount: one['line_count'] is num ? (one['line_count'] as num).toInt() : 0,
      ),
      recurringGrandTotal: total(rec['grand_total']),
      periodLabel: _dec(rec['period_label']),
      termPeriods: rec['term_periods'] is num ? (rec['term_periods'] as num).toInt() : null,
    );
  }

  final ChargePart oneTime;
  final String recurringGrandTotal;

  /// "month" / "quarter" / "45 days" — as the server labels it.
  final String periodLabel;
  final int? termPeriods;
}

/// `POST preview-tax/` answer.
class TaxPreview {
  const TaxPreview({
    required this.taxableTotal,
    required this.grandTotal,
    required this.lines,
    this.summary,
    this.chargeSummary,
  });

  factory TaxPreview.fromJson(Map<String, dynamic> j) => TaxPreview(
        taxableTotal: _dec(j['taxable_total']),
        grandTotal: _dec(j['grand_total']),
        lines: [
          for (final l in (j['line_items'] is List ? j['line_items'] as List : const []))
            if (l is Map) PricedLine.fromJson(Map<String, dynamic>.from(l)),
        ],
        summary: TaxSummary.fromJson(j['tax_summary']),
        chargeSummary: ChargeSummary.fromJson(j['charge_summary']),
      );

  final String taxableTotal;
  final String grandTotal;
  final List<PricedLine> lines;
  final TaxSummary? summary;
  final ChargeSummary? chargeSummary;

  String get shownGrandTotal => summary?.grandTotal ?? grandTotal;
}

/// What the builder previews: create ⇒ the lead or customer; edit ⇒ the quote.
class PreviewContext {
  const PreviewContext({
    required this.isEdit,
    required this.linesDirty,
    required this.savedMode,
    this.quotationId,
    this.leadId,
    this.customerId,
    this.placeOfSupply = '',
  });

  final bool isEdit;

  /// Edit: a line was changed (else the saved lines are the truth).
  final bool linesDirty;

  /// Edit: the mode the quote is saved in.
  final String savedMode;
  final String? quotationId;
  final String? leadId;
  final String? customerId;
  final String placeOfSupply;
}

/// One preview request plus the rows it was built from.
class PreviewRequest {
  const PreviewRequest(this.body, this.rows);
  final Map<String, dynamic> body;
  final List<PreviewRowRef> rows;

  /// A canonical key: equal forms share one request.
  String get key => jsonEncode(body);
}

Map<String, dynamic> _base(PreviewContext c) => {
      if (c.quotationId != null) 'quotation': c.quotationId,
      if (c.leadId != null) 'lead': c.leadId,
      if (c.customerId != null) 'customer': c.customerId,
      'place_of_supply_state_code': c.placeOfSupply.isEmpty ? null : c.placeOfSupply,
    };

/// The live preview for the form as it stands, or null when there is nothing
/// valid to price (a half-typed line keeps the last answer on screen).
PreviewRequest? livePreviewRequest(PreviewContext c, List<QuoteFormItem> items, String mode, String? serverFlip) {
  if (items.any((it) => lineProblem(it) != null)) return null;
  if (c.isEdit && !c.linesDirty) {
    return PreviewRequest({
      ..._base(c),
      if (mode.isNotEmpty) 'amounts_are': mode,
      if (serverFlip != null) 'price_conversion': serverFlip,
    }, previewRowRefs(items));
  }
  final included = includedLines(items);
  if (included.isEmpty && !c.isEdit) return null;
  return PreviewRequest({
    ..._base(c),
    if (mode.isNotEmpty) 'amounts_are': mode,
    'line_items': toLineRows(items),
  }, previewRowRefs(included));
}

/// How a confirmed flip is applied.
enum FlipPlan { serverFlip, resetToSaved, rewriteLines, rewriteLinesDirty }

FlipPlan planFlip(PreviewContext c, String to, String choice) {
  if (c.isEdit && !c.linesDirty) {
    if (to == c.savedMode) return choice == 'convert' ? FlipPlan.resetToSaved : FlipPlan.rewriteLinesDirty;
    return FlipPlan.serverFlip;
  }
  return FlipPlan.rewriteLines;
}

/// The preview that shows what the flip would do, for the Convert / Keep sheet.
PreviewRequest flipPreviewRequest(PreviewContext c, List<QuoteFormItem> items, String from, String to, String choice) {
  final plan = planFlip(c, to, choice);
  if (plan == FlipPlan.serverFlip) {
    return PreviewRequest({..._base(c), 'amounts_are': to, 'price_conversion': choice}, previewRowRefs(items));
  }
  if (plan == FlipPlan.resetToSaved) {
    return PreviewRequest({..._base(c), 'amounts_are': to}, previewRowRefs(items));
  }
  return PreviewRequest({
    ..._base(c),
    'amounts_are': to,
    'source_amounts_are': from,
    'price_conversion': choice,
    'line_items': toLineRows(items),
  }, previewRowRefs(includedLines(items)));
}

/// A 400 from `preview-tax` carries the server's actionable reason; anything
/// else gets plain copy (web `previewErrorCopy`).
String previewErrorCopy(bool isValidation, String message) => isValidation
    ? message
    : 'The tax estimate is unavailable right now. Totals are calculated again when you save.';

const quoteAmountsAreLabels =<String, String>{'EXCLUSIVE': 'Tax exclusive', 'INCLUSIVE': 'Tax inclusive'};
