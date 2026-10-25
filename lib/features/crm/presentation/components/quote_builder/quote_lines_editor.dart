import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/utils/money_format.dart';
import '../../../../accounting/presentation/components/acc_pickers.dart' show PickItem, showSearchPicker;
import '../../../application/providers/quote_builder_providers.dart';
import '../../../application/quote_builder/quote_lines.dart';
import '../../../domain/entities/product.dart';
import '../../../infrastructure/data_sources/remote/quote_builder_remote_ds.dart';
import 'qb_kit.dart';

/// The builder's line items — a port of the web `QuoteLinesEditor`: catalog
/// lines (product picker) and free-text lines, quantity, an **editable** unit
/// price and the server-priced line amount.
///
/// An untouched catalog line shows the server's price in the quote's tax mode
/// ("catalog price") and is sent without a unit price; typing a price pins it
/// and the rotate button ("Use the catalog price") un-pins it. A typed line
/// carries its own HSN/SAC and GST rate. With recurring billing on, each line
/// is billed one-time or recurring.
class QuoteLinesEditor extends ConsumerStatefulWidget {
  const QuoteLinesEditor({
    super.key,
    required this.items,
    required this.onItemsChange,
    required this.catalog,
    required this.catalogLoading,
    required this.priced,
    required this.pricing,
    required this.amountsAre,
    required this.disabled,
    this.recurringEnabled = false,
    this.rateMaster = false,
  });

  final List<QuoteFormItem> items;
  final ValueChanged<List<QuoteFormItem>> onItemsChange;
  final List<Product> catalog;
  final bool catalogLoading;

  /// Row key → the server's priced line(s) (several for a package).
  final Map<String, List<PricedLine>> priced;

  /// A newer preview is on its way — dim the figures.
  final bool pricing;
  final String amountsAre;
  final bool disabled;
  final bool recurringEnabled;

  /// A typed line's GST rate follows its HSN/SAC (accounting tenant).
  final bool rateMaster;

  @override
  ConsumerState<QuoteLinesEditor> createState() => _QuoteLinesEditorState();
}

class _LineCtrls {
  final qty = TextEditingController();
  final price = TextEditingController();
  final name = TextEditingController();
  final hsn = TextEditingController();
  final days = TextEditingController();
  final term = TextEditingController();
  final priceFocus = FocusNode();

  void dispose() {
    for (final c in [qty, price, name, hsn, days, term]) {
      c.dispose();
    }
    priceFocus.dispose();
  }
}

/// What the rate master says about a typed code.
enum _HsnState { loading, found, missing, error }

class _HsnInfo {
  const _HsnInfo(this.state, [this.code]);
  final _HsnState state;
  final HsnCode? code;
}

class _QuoteLinesEditorState extends ConsumerState<QuoteLinesEditor> {
  final _ctrls = <String, _LineCtrls>{};
  final _hsnInfo = <String, _HsnInfo>{};
  Timer? _hsnDebounce;

  @override
  void dispose() {
    _hsnDebounce?.cancel();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  _LineCtrls _ctrlsFor(QuoteFormItem it) => _ctrls.putIfAbsent(it.key, () {
        final c = _LineCtrls();
        c.priceFocus.addListener(() {
          // Focus shows the exact price; blur goes back to the 2-dp display.
          if (mounted) setState(() {});
        });
        return c;
      });

  void _update(String key, QuoteFormItem Function(QuoteFormItem) patch) {
    widget.onItemsChange([for (final it in widget.items) it.key == key ? patch(it) : it]);
  }

  Product? _product(String id) {
    for (final p in widget.catalog) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _pickProduct(QuoteFormItem it) async {
    final usable = [for (final p in widget.catalog) if (p.active || p.id == it.productId) p];
    final id = await showSearchPicker<String>(
      context: context,
      title: 'Select product',
      hint: 'Search products',
      empty: widget.catalogLoading ? 'Loading catalog…' : 'No products in the catalog',
      loading: widget.catalogLoading && usable.isEmpty,
      selected: it.productId,
      items: [
        for (final p in usable)
          PickItem(p.id, p.name,
              subtitle: [formatMoneyStr(p.priceNum), if (p.isPackage) 'Package'].join(' · '),
              searchText: '${p.code} ${p.hsn}'),
      ],
    );
    if (id == null || !mounted) return;
    final p = _product(id);
    _update(it.key, (row) => row.withProduct(id, productName: p?.name ?? '', package: p?.isPackage ?? false));
  }

  // ── HSN / rate master (typed lines) ──────────────────────────────────────

  void _lookupHsn(String code) {
    if (!widget.rateMaster) return;
    final c = code.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(c) || _hsnInfo.containsKey(c)) return;
    _hsnDebounce?.cancel();
    _hsnDebounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _hsnInfo[c] = const _HsnInfo(_HsnState.loading));
      try {
        final results = await ref.read(quoteBuilderDsProvider).hsnSearch(c);
        final hit = resolveHsn(results, c);
        if (mounted) setState(() => _hsnInfo[c] = _HsnInfo(hit == null ? _HsnState.missing : _HsnState.found, hit));
      } on Object {
        if (mounted) setState(() => _hsnInfo[c] = const _HsnInfo(_HsnState.error));
      }
    });
  }

  /// "Pick one from the list": searches the rate master with the typed text.
  Future<void> _pickHsn(QuoteFormItem it) async {
    final q = it.hsnSac.trim();
    if (q.length < 2) return;
    List<HsnCode> results;
    try {
      results = await ref.read(quoteBuilderDsProvider).hsnSearch(q);
    } on Object {
      results = const [];
    }
    if (!mounted) return;
    final code = await showSearchPicker<String>(
      context: context,
      title: 'HSN / SAC',
      empty: 'No rate-master code matches “$q”',
      items: [
        for (final r in results)
          PickItem('${r.code}|${r.supplyNature}', r.code,
              subtitle: r.rates.map((v) => '${formatRate(v.ratePct)}%').toSet().join(' / ')),
      ],
    );
    if (code == null || !mounted) return;
    final picked = results.firstWhere((r) => '${r.code}|${r.supplyNature}' == code);
    _hsnInfo[picked.code] = _HsnInfo(_HsnState.found, picked);
    HsnRate? variant;
    for (final r in picked.rates) {
      if (r.variantKey == picked.defaultVariantKey) variant = r;
    }
    if (variant == null && picked.rates.length == 1) variant = picked.rates.first;
    _update(it.key, (row) => row.copyWith(hsnSac: picked.code, gstRate: variant?.ratePct ?? ''));
  }

  Future<void> _pickGstRate(QuoteFormItem it, {HsnCode? code}) async {
    final options = code != null
        ? [for (final r in code.rates) (r.ratePct, '${formatRate(r.ratePct)}%${r.condition.isEmpty ? '' : ' — ${r.condition}'}')]
        : [('', 'No GST'), for (final r in gstRateOptions(it.gstRate)) (r, '${formatRate(r)}%')];
    final v = await qbPickOne(context, title: 'GST rate', options: options, selected: it.gstRate);
    if (v != null) _update(it.key, (row) => row.copyWith(gstRate: v));
  }

  // ── Display helpers ──────────────────────────────────────────────────────

  String _lineDetail(QuoteFormItem it, List<PricedLine>? lines) {
    if (lines == null || lines.isEmpty) return '';
    if (it.isPackage) {
      final rates = {for (final l in lines) if (l.ratePct != null) '${formatRate(l.ratePct!)}%'};
      return [
        '${lines.length} item${lines.length == 1 ? '' : 's'}',
        if (rates.isNotEmpty) 'GST ${rates.join(', ')}',
      ].join(' · ');
    }
    final l = lines.first;
    return [
      if (l.hsnSac.isNotEmpty) 'HSN/SAC ${l.hsnSac}',
      l.ratePct == null ? 'No GST rate' : 'GST ${formatRate(l.ratePct!)}%',
      if (l.cessPct != null && (double.tryParse(l.cessPct!) ?? 0) != 0) 'Cess ${formatRate(l.cessPct!)}%',
      if ((double.tryParse(l.lineDiscount) ?? 0) != 0) 'Discount −${formatMoneyStr(l.lineDiscount)}',
    ].join(' · ');
  }

  String _lineAmount(QuoteFormItem it, List<PricedLine>? lines) {
    if (lines != null && lines.isNotEmpty) {
      final paise = lines.fold<int>(0, (a, l) => a + ((double.tryParse(l.totalPrice) ?? 0) * 100).round());
      return formatMoneyStr(paise / 100);
    }
    if (sendsOwnPrice(it) && isValidUnitPrice(it.rate)) {
      return formatMoneyStr(toQty(it.qty) * double.parse(cleanUnitPrice(it.rate)));
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    // Drop controllers of removed rows.
    final live = {for (final it in widget.items) it.key};
    for (final k in _ctrls.keys.where((k) => !live.contains(k)).toList()) {
      _ctrls.remove(k)!.dispose();
    }
    final priceHint = switch (widget.amountsAre) {
      'INCLUSIVE' => 'Unit prices include GST',
      'EXCLUSIVE' => 'Unit prices exclude GST',
      _ => '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QbSectionLabel(
          'Line items · from the catalog or typed',
          trailing: priceHint.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(PhosphorIconsRegular.info, size: 13.sp, color: AppColors.textPlaceholder),
                  SizedBox(width: 4.w),
                  Text(priceHint,
                      style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ]),
        ),
        for (var i = 0; i < widget.items.length; i++) ...[
          if (i > 0) SizedBox(height: 10.h),
          _lineCard(widget.items[i]),
        ],
        if (widget.items.any((it) => it.isPackage))
          const QbHint('Package lines expand into their items (with any bundle discount) when the quote is saved.'),
        if (!widget.disabled) ...[
          SizedBox(height: 10.h),
          Row(children: [
            Expanded(
              child: QbAddButton(
                label: 'Add product line',
                icon: PhosphorIconsBold.plus,
                onTap: () => widget.onItemsChange([...widget.items, QuoteFormItem.blank()]),
              ),
            ),
            SizedBox(width: 9.w),
            Expanded(
              child: QbAddButton(
                label: 'Add free-text line',
                icon: PhosphorIconsRegular.pencilLine,
                onTap: () => widget.onItemsChange([...widget.items, QuoteFormItem.blank(LineKind.free)]),
              ),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _lineCard(QuoteFormItem it) {
    final c = _ctrlsFor(it);
    final lines = widget.priced[it.key];
    final problem = lineProblem(it);
    final disabled = widget.disabled;
    final untouchedCatalog = it.kind == LineKind.catalog && !it.priceTouched && !it.isPackage;
    final serverPrice = lines != null && lines.length == 1 && !it.isPackage ? lines.first.unitPrice : '';
    final raw = it.priceTouched || it.kind == LineKind.free ? it.rate : serverPrice;
    final focused = c.priceFocus.hasFocus;
    if (!focused) qbSync(c.price, raw.isEmpty ? '' : displayUnitPrice(raw, toQty(it.qty)));
    qbSync(c.qty, it.qty);
    if (it.kind == LineKind.free) {
      qbSync(c.name, it.name);
      qbSync(c.hsn, it.hsnSac);
    }
    final detail = _lineDetail(it, lines);
    final sub = [detail, if (untouchedCatalog && it.productId.isNotEmpty) 'catalog price'].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(13.r),
        border: Border.all(color: const Color(0xFFE6E7EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (it.kind == LineKind.catalog)
            QbPickerBox(
              text: it.productId.isEmpty ? '' : (_product(it.productId)?.name ?? (it.name.isEmpty ? 'Product' : it.name)),
              placeholder: widget.catalogLoading ? 'Loading catalog…' : 'Select product…',
              onTap: disabled ? null : () => _pickProduct(it),
            )
          else
            QbBox(
              controller: c.name,
              enabled: !disabled,
              hint: 'Describe the item or service',
              maxLength: 500,
              error: problem == LineProblem.description,
              onChanged: (v) => _update(it.key, (row) => row.copyWith(name: v)),
            ),
          if (it.kind == LineKind.free && !disabled) ...[
            SizedBox(height: 9.h),
            _freeTax(it, c),
          ],
          SizedBox(height: 9.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 74.w,
                child: QbBox(
                  controller: c.qty,
                  enabled: !disabled,
                  numeric: true,
                  hint: 'Qty',
                  align: TextAlign.center,
                  error: problem == LineProblem.qty,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    // Digits, one dot, at most three decimals (the server's 3 dp).
                    TextInputFormatter.withFunction(
                        (o, n) => RegExp(r'^\d*\.?\d{0,3}$').hasMatch(n.text) ? n : o),
                  ],
                  onChanged: (v) => _update(it.key, (row) => row.copyWith(qty: v)),
                ),
              ),
              SizedBox(width: 9.w),
              Expanded(
                child: it.isPackage
                    ? Tooltip(
                        message: 'A package is priced from the catalog and expands into its items when saved.',
                        child: Text('Package',
                            textAlign: TextAlign.center,
                            style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textMuted)),
                      )
                    : QbBox(
                        controller: c.price,
                        focusNode: c.priceFocus,
                        enabled: !disabled,
                        numeric: true,
                        align: TextAlign.end,
                        muted: untouchedCatalog,
                        hint: it.kind == LineKind.free ? '0.00' : (it.productId.isNotEmpty ? '…' : 'Unit price'),
                        error: problem == LineProblem.price,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,₹ ]'))],
                        onChanged: (v) => _update(it.key, (row) => row.copyWith(rate: v, priceTouched: true)),
                        suffix: it.kind == LineKind.catalog && it.priceTouched && it.productId.isNotEmpty && !disabled
                            ? GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  c.priceFocus.unfocus();
                                  _update(it.key, (row) => row.withCatalogPrice());
                                },
                                child: Tooltip(
                                  message: 'Use the catalog price',
                                  child: Padding(
                                    padding: EdgeInsets.all(6.w),
                                    child: Icon(PhosphorIconsRegular.arrowCounterClockwise,
                                        size: 15.sp, color: AppColors.textLabelAlt, semanticLabel: 'Use the catalog price'),
                                  ),
                                ),
                              )
                            : null,
                      ),
              ),
              SizedBox(width: 8.w),
              Opacity(
                opacity: widget.pricing ? 0.6 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Amount', style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                    Text(_lineAmount(it, lines),
                        style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                  ],
                ),
              ),
              if (!disabled) ...[
                SizedBox(width: 8.w),
                QbIconButton(
                  icon: PhosphorIconsRegular.trash,
                  danger: true,
                  tooltip: 'Remove line',
                  onTap: () => widget.onItemsChange([for (final r in widget.items) if (r.key != it.key) r]),
                ),
              ],
            ],
          ),
          if (sub.isNotEmpty)
            Opacity(opacity: widget.pricing ? 0.6 : 1, child: QbHint(sub)),
          if (widget.recurringEnabled && (it.productId.isNotEmpty || it.name.trim().isNotEmpty)) ...[
            SizedBox(height: 8.h),
            disabled ? QbHint(chargeLabel(effectiveCharge(it, lines))) : _chargeControl(it, c, effectiveCharge(it, lines)),
          ],
        ],
      ),
    );
  }

  Widget _freeTax(QuoteFormItem it, _LineCtrls c) {
    final taxProblem = freeLineTaxProblem(it);
    final code = it.hsnSac.trim();
    final info = _hsnInfo[code];
    final found = info?.state == _HsnState.found ? info!.code : null;
    final hsnError = taxProblem == FreeTaxProblem.hsn
        ? 'HSN / SAC must be 4 to 8 digits.'
        : widget.rateMaster && info?.state == _HsnState.missing
            ? 'This code is not in the GST rate master — pick one from the list.'
            : null;
    final variantMissing = widget.rateMaster &&
        found != null &&
        found.needsVariantChoice &&
        !found.rates.any((r) => it.gstRate.isNotEmpty && double.tryParse(r.ratePct) == double.tryParse(it.gstRate));
    if (widget.rateMaster && code.isNotEmpty) _lookupHsn(code);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const QbFieldLabel('HSN / SAC'),
              SizedBox(height: 6.h),
              QbBox(
                controller: c.hsn,
                numeric: true,
                hint: 'e.g. 998313',
                error: hsnError != null,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                // On a rate-master tenant the rate is the code's: forget the old code's rate.
                onChanged: (v) => _update(it.key, (row) => row.copyWith(hsnSac: v, gstRate: widget.rateMaster ? '' : null)),
                suffix: widget.rateMaster
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _pickHsn(it),
                        child: Padding(
                          padding: EdgeInsets.all(6.w),
                          child: Icon(PhosphorIconsRegular.magnifyingGlass, size: 15.sp, color: AppColors.textLabelAlt),
                        ),
                      )
                    : null,
              ),
            ]),
          ),
          SizedBox(width: 9.w),
          SizedBox(
            width: 128.w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const QbFieldLabel('GST rate'),
              SizedBox(height: 6.h),
              if (!widget.rateMaster)
                QbPickerBox(
                  text: it.gstRate.isEmpty ? 'No GST' : '${formatRate(it.gstRate)}%',
                  placeholder: 'No GST',
                  error: taxProblem == FreeTaxProblem.rate,
                  onTap: () => _pickGstRate(it),
                )
              else
                QbPickerBox(
                  text: it.gstRate.isEmpty
                      ? (found != null && !found.needsVariantChoice && found.rates.isNotEmpty
                          ? '${formatRate(found.rates.first.ratePct)}%'
                          : '')
                      : '${formatRate(it.gstRate)}%',
                  placeholder: info?.state == _HsnState.loading ? 'Looking up…' : 'From the code',
                  error: variantMissing,
                  onTap: found != null && found.rates.length > 1 ? () => _pickGstRate(it, code: found) : null,
                ),
            ]),
          ),
        ]),
        if (hsnError != null) QbHint(hsnError, error: true),
        if (variantMissing) const QbHint('Choose the GST rate for this code.', error: true),
      ],
    );
  }

  Widget _chargeControl(QuoteFormItem it, _LineCtrls c, LineCharge charge) {
    final problem = chargeProblem(charge);
    qbSync(c.days, charge.billingPeriodDays?.toString() ?? '');
    qbSync(c.term, charge.termPeriods?.toString() ?? '');
    int? intOrNull(String v) => v.trim().isEmpty ? null : int.tryParse(v.trim());
    void set(LineCharge next) => _update(it.key, (row) => row.copyWith(charge: next));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6.w,
          runSpacing: 6.h,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Billed', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            QbChip(
              label: 'One-time',
              selected: !charge.isRecurring,
              onTap: () => set(LineCharge.oneTime),
            ),
            QbChip(
              label: 'Recurring',
              selected: charge.isRecurring,
              onTap: () => set(LineCharge(
                chargeType: ChargeType.recurring,
                billingPeriod: charge.billingPeriod ?? 'month',
                billingPeriodDays: charge.billingPeriodDays,
                termPeriods: charge.termPeriods,
              )),
            ),
          ],
        ),
        if (charge.isRecurring) ...[
          SizedBox(height: 8.h),
          Row(children: [
            Expanded(
              child: QbPickerBox(
                height: 38.h,
                text: billingPeriodLabels[charge.billingPeriod ?? 'month'] ?? '',
                placeholder: 'Billing period',
                onTap: () async {
                  final v = await qbPickOne(context,
                      title: 'Billing period',
                      options: [for (final p in billingPeriods) (p, billingPeriodLabels[p]!)],
                      selected: charge.billingPeriod);
                  if (v != null) {
                    set(charge.copyWith(
                        billingPeriod: v, billingPeriodDays: v == 'custom_days' ? (charge.billingPeriodDays ?? 30) : null));
                  }
                },
              ),
            ),
            if (charge.billingPeriod == 'custom_days') ...[
              SizedBox(width: 6.w),
              SizedBox(
                width: 64.w,
                child: QbBox(
                  controller: c.days,
                  height: 38.h,
                  numeric: true,
                  hint: 'days',
                  align: TextAlign.end,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => set(charge.copyWith(billingPeriodDays: intOrNull(v))),
                ),
              ),
            ],
            SizedBox(width: 6.w),
            Text('for', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
            SizedBox(width: 6.w),
            SizedBox(
              width: 56.w,
              child: QbBox(
                controller: c.term,
                height: 38.h,
                numeric: true,
                hint: '∞',
                align: TextAlign.end,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) => set(charge.copyWith(termPeriods: intOrNull(v))),
              ),
            ),
          ]),
          QbHint(charge.termPeriods != null ? 'periods' : 'periods (blank = until cancelled)'),
        ],
        if (problem != null) QbHint(problem, error: true),
      ],
    );
  }
}
