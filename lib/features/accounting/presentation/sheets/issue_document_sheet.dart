import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../../crm/presentation/sheets/add_sheet_kit.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../../domain/entities/acc_settlement.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';
import 'acc_sheet_scaffold.dart';

/// What the issue sheet asks its caller to do next when it cannot finish on
/// its own.
enum IssueFollowUp { editDraft, voidDraft }

/// Opens the "Preview & issue" sheet (plan §4.5). Resolves to the issued
/// document, an [IssueFollowUp] the caller should run, or null.
Future<Object?> showIssueSheet(BuildContext context, AccDocument doc) => showClozrSheet<Object>(
      context: context,
      builder: (_) => _IssueSheet(doc: doc),
    );

class _IssueSheet extends ConsumerStatefulWidget {
  const _IssueSheet({required this.doc});
  final AccDocument doc;

  @override
  ConsumerState<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends ConsumerState<_IssueSheet> {
  TaxPreview? _preview;
  AppError? _previewError;
  AppError? _error;
  bool _busy = false;

  /// `advance_id → amount` the user chose to adjust against this invoice.
  final Map<String, TextEditingController> _adjust = {};

  /// Set when issue answered `RATE_VARIANT_REQUIRED`.
  List<RateVariant> _candidates = const [];
  int? _variantLine;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    for (final c in _adjust.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _preview = null;
      _previewError = null;
    });
    try {
      final p = await ref.read(accountingRepositoryProvider).previewTax(widget.doc.id);
      if (mounted) setState(() => _preview = p);
    } on AppError catch (e) {
      if (mounted) setState(() => _previewError = e);
    }
  }

  List<Map<String, String>> get _adjustments => [
        for (final e in _adjust.entries)
          if (moneyInput(e.value.text) != null && !moneyIsZero(moneyInput(e.value.text)))
            {'advance_id': e.key, 'amount': moneyInput(e.value.text)!},
      ];

  Future<void> _issue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final issued = await ref.read(accountingRepositoryProvider).issue(widget.doc.id, advanceAdjustments: _adjustments);
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Issued ${issued?.number ?? 'invoice'}');
      Navigator.of(context).pop(issued);
    } on AppError catch (e) {
      if (!mounted) return;
      if (e.isAccountingInactive) ref.invalidate(accountingStatusProvider);
      setState(() {
        _busy = false;
        _error = e;
        if (e.code == 'RATE_VARIANT_REQUIRED') {
          final cands = e.causeMap['candidates'];
          _candidates = [
            if (cands is List)
              for (final c in cands)
                if (c is Map && (c['variant_key'] ?? c['rate_variant_key']) != null)
                  RateVariant(
                    variantKey: '${c['variant_key'] ?? c['rate_variant_key']}',
                    hsnSac: c['hsn_sac']?.toString(),
                    ratePct: c['rate_pct']?.toString(),
                    description: c['description']?.toString(),
                  ),
          ];
          _variantLine = int.tryParse('${e.causeMap['line_no'] ?? ''}');
        } else {
          _candidates = const [];
        }
      });
    }
  }

  /// Pins the chosen variant on the line's product, then retries the issue.
  Future<void> _pinVariant(RateVariant v) async {
    final line = widget.doc.lines.where((l) => l.lineNo == _variantLine).firstOrNull;
    final productId = line?.productId;
    if (productId == null) {
      ref.read(toastProvider.notifier).showError(
          'That line has no catalog product to save the rate on. Void this draft and add the line from a product.');
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(accountingRepositoryProvider);
      final current = await repo.productTaxProfile(productId);
      await repo.saveProductTaxProfile(productId, {
        'tax_treatment_default': current.taxTreatmentDefault ?? 'TAXABLE',
        'rate_variant_key': v.variantKey,
        'is_rcm_outward': current.isRcmOutward,
        'cess_applicable': current.cessApplicable,
      });
      ref.invalidate(productTaxProfileProvider(productId));
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _candidates = const [];
    });
    await _loadPreview();
    await _issue();
  }

  (String?, VoidCallback?) get _errorAction {
    switch (_error?.code) {
      case 'AMOUNTS_ARE_REQUIRED':
      case 'PERIOD_FILED_DATE_IN_OPEN_PERIOD':
        return ('Edit draft', () => Navigator.of(context).pop(IssueFollowUp.editDraft));
      case 'HSN_DIGITS_REQUIRED':
      case 'CUSTOMER_REQUIRED':
        return ('Void this draft', () => Navigator.of(context).pop(IssueFollowUp.voidDraft));
      default:
        return (null, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approve = ref.watch(accPermProvider('acc_document')).approve;
    final (actionLabel, onAction) = _errorAction;
    return AccSheetScaffold(
      title: 'Preview & issue',
      submitLabel: 'Issue invoice',
      submitIcon: PhosphorIconsBold.sealCheck,
      busy: _busy,
      busyLabel: 'Issuing…',
      submitEnabled: approve && _preview != null,
      error: _error,
      errorAction: actionLabel,
      onErrorAction: onAction,
      onSubmit: _issue,
      children: [
        if (!approve)
          const AccInfoBanner('Issuing needs approve rights on invoices. Ask someone who has them.',
              icon: PhosphorIconsRegular.lock),
        if (_candidates.isNotEmpty) _variantPicker(),
        ..._previewBody(),
        if (widget.doc.customerId != null) _advances(widget.doc.customerId!),
        const AccInfoBanner(
          'Issuing numbers the invoice and posts it to the ledger. After that it can only be cancelled or credited.',
        ),
      ],
    );
  }

  List<Widget> _previewBody() {
    if (_previewError != null) {
      return [ConflictBanner(error: _previewError!, actionLabel: 'Try again', onAction: _loadPreview)];
    }
    final p = _preview;
    if (p == null) {
      return [
        SizedBox(
          height: 120.h,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy)),
        ),
      ];
    }
    final unverified = p.configRows.where((c) => !c.isVerified).length;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              [
                if (p.supply != null) p.supply == 'INTER' ? 'Inter-state (IGST)' : 'Intra-state (CGST + SGST)',
                if (p.transactionClass != null) label(transactionClassLabels, p.transactionClass),
                if (p.amountsAre != null) label(amountsAreLabels, p.amountsAre),
              ].join(' · '),
              style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
      AccTotalsCard(totals: p.totals, title: 'If issued now'),
      FinanceCard(
        title: 'Rates used',
        child: Column(
          children: [
            for (int i = 0; i < p.lines.length; i++)
              MetaRow(
                label: 'Line ${p.lines[i].lineNo}${p.lines[i].hsnSac == null ? '' : ' · ${p.lines[i].hsnSac}'}',
                value: p.lines[i].ratePct == null
                    ? 'No rate found'
                    : '${p.lines[i].ratePct}%${p.lines[i].matchLevel == null ? '' : ' · ${label(const {}, p.lines[i].matchLevel)}'}',
                last: i == p.lines.length - 1,
              ),
          ],
        ),
      ),
      if (unverified > 0)
        AccInfoBanner(
          '$unverified rate ${unverified == 1 ? 'row is' : 'rows are'} not yet verified — ask your accountant to confirm them.',
          icon: PhosphorIconsRegular.sealWarning,
        ),
      WarningsStrip(warnings: p.warnings),
    ];
  }

  Widget _variantPicker() {
    return FinanceCard(
      title: 'Choose the rate for line ${_variantLine ?? ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('It is saved on the product, so the next invoice picks it up on its own.',
              style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
          SizedBox(height: 8.h),
          for (final v in _candidates)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _busy ? null : () => _pinVariant(v),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(v.description ?? v.variantKey,
                          style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textPrimary)),
                    ),
                    Text('${v.ratePct ?? '—'}%',
                        style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.navy)),
                    SizedBox(width: 8.w),
                    Icon(PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.textPlaceholder),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Open taxed advances of this customer that can be set off at issue.
  Widget _advances(String customerId) {
    final async = ref.watch(advancesProvider(customerId));
    final open = [for (final a in async.valueOrNull ?? const <AccAdvance>[]) if (a.isOpen) a];
    if (open.isEmpty) return const SizedBox.shrink();
    return AccDisclosure(
      title: 'Adjust advances (${open.length})',
      children: [
        Text('Advances this customer paid before the invoice. Enter how much of each to set off.',
            style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
        for (final a in open)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SheetFieldLabel('Advance'),
                    Text('${formatMoneyStr(a.remainingTaxable)} open',
                        style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text([label(supplyNatureLabels, a.supplyNature), if (a.ratePct != null) '${a.ratePct}%'].join(' · '),
                        style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: MoneyField(
                  label: 'Adjust',
                  controller: _adjust.putIfAbsent(a.id, TextEditingController.new),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
