import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/utils/money_format.dart';
import '../../../application/quote_builder/quote_builder_draft.dart';
import '../../../application/quote_builder/quote_tax.dart';
import 'qb_kit.dart';

/// The builder's totals — the server's GST estimate (web `QuoteTotalsBlock` +
/// `TaxTotalsPanel`): Sub-total, CGST + SGST or IGST "(estimate)", Cess,
/// Round off, Grand total, the recurring split, the discount as last saved and
/// the estimate note. Nothing here computes tax.
class QuoteTotalsBlock extends StatelessWidget {
  const QuoteTotalsBlock({
    super.key,
    required this.summary,
    this.taxableTotal,
    this.grandTotal,
    this.loading = false,
    this.updating = false,
    this.error,
    this.discountPct = '',
    this.chargeSummary,
  });

  /// The figures to show; null = nothing priced yet.
  final TaxSummary? summary;

  /// Fallbacks when the response has no `tax_summary` (older backend).
  final String? taxableTotal;
  final String? grandTotal;
  final bool loading;
  final bool updating;
  final String? error;

  /// `discount_pct` as last saved; '' or 0 hides the row.
  final String discountPct;
  final ChargeSummary? chargeSummary;

  @override
  Widget build(BuildContext context) {
    final rows = taxTotalsRows(summary, taxableFallback: taxableTotal ?? '0');
    final isEstimate = summary?.isEstimate ?? true;
    final grand = summary?.grandTotal ?? grandTotal ?? '0';
    final hasDiscount = (double.tryParse(discountPct) ?? 0) > 0;
    final warnings = summary?.warnings ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(13.r),
            border: Border.all(color: const Color(0xFFE6E7EA)),
          ),
          child: loading
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  child: const Center(
                    child: SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy)),
                  ),
                )
              : Opacity(
                  opacity: updating ? 0.6 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (error != null)
                        Padding(
                          padding: EdgeInsets.only(bottom: 8.h),
                          child: Text(error!,
                              style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.error)),
                        ),
                      for (final r in rows)
                        _row(r.label + (r.isTax && isEstimate ? ' (estimate)' : ''), _fig(r.value)),
                      Container(
                        margin: EdgeInsets.only(top: 4.h),
                        padding: EdgeInsets.only(top: 9.h),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text('Grand total',
                                  style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                            ),
                            Text(_fig(grand),
                                style: AppText.custom(
                                    size: 20, weight: FontWeight.w800, color: AppColors.navy, letterSpacing: -0.4)),
                          ],
                        ),
                      ),
                      if (chargeSummary != null) _chargeSplit(chargeSummary!),
                      if (hasDiscount)
                        Padding(
                          padding: EdgeInsets.only(top: 8.h),
                          child: _row('Discount (as last saved)', pct2(discountPct)),
                        ),
                    ],
                  ),
                ),
        ),
        const QbHint(estimateNote, align: TextAlign.end),
        if (warnings.isNotEmpty) ...[
          SizedBox(height: 8.h),
          QbNotice(
            tone: QbTone.warning,
            icon: PhosphorIconsRegular.warning,
            children: [for (final w in warnings) qbNoticeText(w)],
          ),
        ],
      ],
    );
  }

  /// A missing figure is a dash — never "₹0.00", which reads like a total.
  static String _fig(String v) => v.isEmpty ? '—' : formatMoneyStr(v);

  Widget _row(String label, String value) => Padding(
        padding: EdgeInsets.only(bottom: 6.h),
        child: Row(children: [
          Expanded(
            child: Text(label, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
          ),
          Text(value, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
        ]),
      );

  /// One-time / Recurring (per period) / First invoice — the server's figures.
  Widget _chargeSplit(ChargeSummary s) {
    final hasOneTime = s.oneTime.lineCount > 0;
    final per = '${formatMoneyStr(s.recurringGrandTotal)} / ${s.periodLabel}';
    return Container(
      margin: EdgeInsets.only(top: 10.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(10.r)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (hasOneTime) _row('One-time', formatMoneyStr(s.oneTime.grandTotal)),
        _row('Recurring', '$per ${termLabelFor(s.termPeriods)}'),
        _row(
            'First invoice',
            hasOneTime
                ? '${formatMoneyStr(s.oneTime.grandTotal)} + ${formatMoneyStr(s.recurringGrandTotal)}'
                : formatMoneyStr(s.recurringGrandTotal)),
        Text('Amounts include GST, charged on each invoice; the recurring amount is per ${s.periodLabel}.',
            style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
      ]),
    );
  }

  static String termLabelFor(int? term) => term != null && term > 0 ? '× $term' : 'until cancelled';
}

/// One unit price that a tax-mode flip changes.
class PriceChangeRow {
  const PriceChangeRow({required this.name, required this.before, required this.after});
  final String name;
  final String before;
  final String after;
}

/// "Change how amounts are entered?" — Convert prices (total stays) / Keep
/// prices (total changes), with the server-previewed RESULT. Returns the
/// confirmed choice, or null on Cancel.
///
/// [preview] is called with a choice and resolves to the flip's figures; the
/// sheet re-asks whenever the choice changes.
Future<String?> showPriceConversionSheet(
  BuildContext context, {
  required String from,
  required String to,
  required String? grandTotalBefore,
  required Future<({String? grandTotalAfter, List<PriceChangeRow> changes, String? error})> Function(String choice)
      preview,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _PriceConversionSheet(from: from, to: to, before: grandTotalBefore, preview: preview),
  );
}

class _PriceConversionSheet extends StatefulWidget {
  const _PriceConversionSheet({required this.from, required this.to, required this.before, required this.preview});
  final String from;
  final String to;
  final String? before;
  final Future<({String? grandTotalAfter, List<PriceChangeRow> changes, String? error})> Function(String) preview;

  @override
  State<_PriceConversionSheet> createState() => _PriceConversionSheetState();
}

class _PriceConversionSheetState extends State<_PriceConversionSheet> {
  String _choice = 'convert';
  bool _loading = true;
  ({String? grandTotalAfter, List<PriceChangeRow> changes, String? error})? _result;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final r = await widget.preview(_choice);
    if (!mounted || seq != _seq) return;
    setState(() {
      _result = r;
      _loading = false;
    });
  }

  static String _words(String mode) => mode == 'INCLUSIVE' ? 'inclusive of GST' : 'exclusive of GST';

  @override
  Widget build(BuildContext context) {
    final opts = [
      (
        'convert',
        'Convert prices (total stays)',
        'Each unit price is re-expressed ${_words(widget.to)}, so what the customer pays stays the same. Catalog lines are re-priced from the catalog.'
      ),
      (
        'keep',
        'Keep prices (total changes)',
        'Unit prices stay as they are and are now read as ${_words(widget.to)}, so the grand total changes.'
      ),
    ];
    final r = _result;
    final canApply = !_loading && r != null && r.error == null;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: BoxDecoration(color: AppColors.bgApp, borderRadius: BorderRadius.vertical(top: Radius.circular(24.r))),
      padding: EdgeInsets.fromLTRB(18.w, 18.h, 18.w, 22.h),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Change how amounts are entered?',
                style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
            SizedBox(height: 8.h),
            Text.rich(TextSpan(
              style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textBody),
              children: [
                const TextSpan(text: 'Amounts are: '),
                TextSpan(text: quoteAmountsAreLabels[widget.from], style: const TextStyle(fontWeight: FontWeight.w800)),
                const TextSpan(text: ' → '),
                TextSpan(text: quoteAmountsAreLabels[widget.to], style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            )),
            SizedBox(height: 12.h),
            for (final o in opts)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_choice == o.$1) return;
                  setState(() => _choice = o.$1);
                  _load();
                },
                child: Container(
                  margin: EdgeInsets.only(bottom: 10.h),
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                        color: _choice == o.$1 ? AppColors.navy : const Color(0xFFE6E7EA), width: _choice == o.$1 ? 1.5 : 1),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(_choice == o.$1 ? PhosphorIconsFill.radioButton : PhosphorIconsRegular.circle,
                        size: 18.sp, color: _choice == o.$1 ? AppColors.navy : AppColors.textPlaceholder),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.$2, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 3.h),
                        Text(o.$3, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                      ]),
                    ),
                  ]),
                ),
              ),
            SizedBox(height: 4.h),
            Text('RESULT',
                style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
            SizedBox(height: 8.h),
            if (_loading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12.h),
                child: const Center(
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))),
              )
            else if (r?.error != null)
              QbNotice(tone: QbTone.danger, icon: PhosphorIconsRegular.warningCircle, children: [qbNoticeText(r!.error!)])
            else ...[
              _resultRow('Grand total (estimate)',
                  '${widget.before != null ? '${formatMoneyStr(widget.before)} → ' : ''}${formatMoneyStr(r?.grandTotalAfter)}',
                  strong: true),
              for (final c in (r?.changes ?? const <PriceChangeRow>[]).take(4)) _resultRow(c.name, '₹${c.before} → ₹${c.after}'),
              if ((r?.changes.length ?? 0) > 4) QbHint('…and ${r!.changes.length - 4} more line(s).'),
              if ((r?.changes.length ?? 0) == 0) const QbHint('No unit price changes.'),
            ],
            SizedBox(height: 16.h),
            Row(children: [
              Expanded(
                child: _button('Cancel', primary: false, onTap: () => Navigator.of(context).pop()),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _button('Apply', primary: true, onTap: canApply ? () => Navigator.of(context).pop(_choice) : null),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value, {bool strong = false}) => Padding(
        padding: EdgeInsets.only(bottom: 6.h),
        child: Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.custom(size: strong ? 13.5 : 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
          ),
          SizedBox(width: 10.w),
          Text(value,
              style: AppText.custom(
                  size: strong ? 13.5 : 12.5,
                  weight: strong ? FontWeight.w800 : FontWeight.w600,
                  color: AppColors.textPrimary)),
        ]),
      );
}

/// The app's 48h footer button (navy primary / outlined secondary).
Widget _button(String label, {required bool primary, VoidCallback? onTap}) => GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? (onTap == null ? AppColors.textPlaceholder : AppColors.navy) : AppColors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: primary ? null : Border.all(color: const Color(0xFFE6E7EA)),
        ),
        child: Text(label,
            style: AppText.custom(
                size: 14.5, weight: FontWeight.w700, color: primary ? AppColors.white : AppColors.textLabelAlt)),
      ),
    );

/// Shared with the other builder sheets.
Widget qbSheetButton(String label, {required bool primary, VoidCallback? onTap}) =>
    _button(label, primary: primary, onTap: onTap);
