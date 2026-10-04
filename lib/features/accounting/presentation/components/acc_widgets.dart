import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/connectivity_provider.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/presentation/components/crm_check_box.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../../crm/presentation/sheets/add_sheet_kit.dart';
import '../../application/providers/accounting_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../../domain/entities/acc_setup.dart';
import '../config/accounting_copy.dart';

/// The prototype's `#35507C` info-banner text — no design token exists for it
/// (the same constant the payments screens keep locally).
const Color kBannerText = Color(0xFF35507C);

/// Renders [child] only once accounting is known to be open, and the right
/// empty state otherwise — not activated, not in the plan, no permission.
///
/// Every accounting screen body goes through this, so a Starter-plan user or
/// an org that never activated sees one honest sentence instead of a screen of
/// 403s and 409s.
class AccountingGate extends ConsumerWidget {
  const AccountingGate({super.key, required this.child, this.allowInactive = false});

  final Widget child;

  /// The Status screen is readable before activation (setup endpoints skip the
  /// activation gate), so it opts in.
  final bool allowInactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(accountingStatusProvider);
    return status.when(
      skipLoadingOnRefresh: true,
      loading: () => const DetailSkeleton(),
      error: (e, _) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ErrorState.forError(
            e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Something went wrong.'),
            onRetry: () => ref.invalidate(accountingStatusProvider),
          ),
        ],
      ),
      data: (s) {
        if (s == AccountingStatus.active) return child;
        if (allowInactive && (s == AccountingStatus.inactive || s == AccountingStatus.paused)) return child;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [_empty(context, s)],
        );
      },
    );
  }

  Widget _empty(BuildContext context, AccountingStatus s) {
    switch (s) {
      case AccountingStatus.notInPlan:
        return const EmptyState(
          icon: PhosphorIconsRegular.lockSimple,
          title: 'Not in your plan',
          body: 'Accounting is not included in your current plan. Upgrade on the web app.',
        );
      case AccountingStatus.noAccess:
        return const EmptyState(
          icon: PhosphorIconsRegular.lock,
          title: 'No access',
          body: 'Your role does not include accounting. Ask an admin for access.',
        );
      case AccountingStatus.unavailable:
        return const EmptyState(
          icon: PhosphorIconsRegular.calculator,
          title: 'Accounting needs a backend',
          body: 'Accounting is not available in the demo build.',
        );
      case AccountingStatus.paused:
        return EmptyState(
          icon: PhosphorIconsRegular.pauseCircle,
          title: 'Accounting is paused',
          body: 'The books are activating or suspended. Check the status for details.',
          ctaLabel: 'View status',
          onCta: () => context.push(Routes.accStatus),
        );
      case AccountingStatus.inactive:
      case AccountingStatus.unknown:
      case AccountingStatus.active:
        return EmptyState(
          icon: PhosphorIconsRegular.calculator,
          title: 'Accounting is not activated',
          body: 'Set it up on the web app first. You can see what is missing on the status screen.',
          ctaLabel: 'View status',
          ctaIcon: PhosphorIconsBold.arrowRight,
          onCta: () => context.push(Routes.accStatus),
        );
    }
  }
}

/// The inline refusal a posting sheet shows — title, the explanation and up to
/// three `cause` chips, with an optional action for the `next` hint.
///
/// Rendered inside the sheet rather than only toasted: the `cause` is the part
/// that tells the user what to fix, and a toast is gone before it is read.
class ConflictBanner extends StatelessWidget {
  const ConflictBanner({super.key, required this.error, this.actionLabel, this.onAction});

  final AppError error;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final copy = error.code == null
        ? (title: 'Could not complete', body: error.message)
        : conflictCopy(error);
    final chips = <String>[
      for (final e in error.causeMap.entries)
        if (e.value is String || e.value is num) '${label(const {}, e.key)}: ${e.value}',
    ].take(3).toList();
    return Container(
      padding: EdgeInsets.fromLTRB(13.w, 12.h, 13.w, 12.h),
      decoration: BoxDecoration(
        color: AppColors.tintRed,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.error.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.warningCircle, size: 17.sp, color: AppColors.error),
          SizedBox(width: 9.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(copy.title, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.errorDeep)),
                SizedBox(height: 3.h),
                Text(copy.body,
                    style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textSecondary, height: 1.45)),
                if (chips.isNotEmpty) ...[
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 6.w,
                    runSpacing: 6.h,
                    children: [
                      for (final c in chips)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(7.r)),
                          child: Text(c, style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textLabel)),
                        ),
                    ],
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  SizedBox(height: 9.h),
                  GestureDetector(
                    onTap: onAction,
                    child: Text(actionLabel!,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.blueBright)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Amber strip listing a document's or preview's warnings. Not errors — the
/// document is fine, these are things to know.
class WarningsStrip extends StatelessWidget {
  const WarningsStrip({super.key, required this.warnings, this.configDraftRows = 0});

  final List<DocWarning> warnings;
  final int configDraftRows;

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final w in warnings) warningCopy(w),
      if (configDraftRows > 0 && !warnings.any((w) => w.code == 'DRAFT_CONFIG_USED'))
        'Some tax rates used are not yet verified by your accountant.',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.fromLTRB(13.w, 11.h, 13.w, 11.h),
      decoration: BoxDecoration(color: AppColors.tintAmber, borderRadius: BorderRadius.circular(12.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.warning, size: 16.sp, color: AppColors.warningDeep),
          SizedBox(width: 9.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < lines.length; i++) ...[
                  if (i > 0) SizedBox(height: 5.h),
                  Text(lines[i],
                      style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The blue explanatory banner the finance sheets use.
class AccInfoBanner extends StatelessWidget {
  const AccInfoBanner(this.text, {super.key, this.icon = PhosphorIconsRegular.info});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
      decoration: BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(10.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15.sp, color: AppColors.blueBright),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(text, style: AppText.custom(size: 12, weight: FontWeight.w500, color: kBannerText, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

/// A document's status pill.
class DocStatusPill extends StatelessWidget {
  const DocStatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) =>
      StatusPill.meta(StatusMeta$.accDocument[status] ?? StatusMeta(label(const {}, status), AppColors.textMuted));
}

/// A document's payment-state pill; renders nothing for `NA`.
class PaymentStatePill extends StatelessWidget {
  const PaymentStatePill(this.state, {super.key});
  final String state;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.accPaymentState[state];
    return meta == null ? const SizedBox.shrink() : StatusPill.meta(meta);
  }
}

/// A pill from any accounting vocabulary map, with a humanised fallback.
class AccPill extends StatelessWidget {
  const AccPill(this.map, this.value, {super.key});
  final Map<String, StatusMeta> map;
  final String value;

  @override
  Widget build(BuildContext context) =>
      StatusPill.meta(map[value] ?? StatusMeta(label(const {}, value), AppColors.textMuted));
}

/// A document's money breakdown: taxable value, each tax head that is not
/// zero, round-off and the grand total. Draft figures are provisional — the
/// server recomputes them at issue — so they carry an "estimated" note.
class AccTotalsCard extends StatelessWidget {
  const AccTotalsCard({super.key, required this.totals, this.estimated = false, this.title = 'Totals', this.extra = const []});

  /// `taxable_total, tax_cgst, tax_sgst, tax_igst, tax_cess, round_off,
  /// grand_total` as money strings.
  final Map<String, String> totals;
  final bool estimated;
  final String title;

  /// Rows appended after the grand total (paid, open balance, TDS…).
  final List<(String, String)> extra;

  static Map<String, String> ofDocument(AccDocument d) => {
        'taxable_total': d.taxableTotal,
        'tax_cgst': d.taxCgst,
        'tax_sgst': d.taxSgst,
        'tax_igst': d.taxIgst,
        'tax_cess': d.taxCess,
        'round_off': d.roundOff,
        'grand_total': d.grandTotal,
      };

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Taxable value', totals['taxable_total'] ?? '0'),
      for (final h in const [('CGST', 'tax_cgst'), ('SGST', 'tax_sgst'), ('IGST', 'tax_igst'), ('Cess', 'tax_cess')])
        if (!moneyIsZero(totals[h.$2])) (h.$1, totals[h.$2]!),
      if (!moneyIsZero(totals['round_off'])) ('Round-off', totals['round_off']!),
    ];
    return FinanceCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows) MetaRow(label: r.$1, value: formatMoneyStr(r.$2)),
          Padding(
            padding: EdgeInsets.only(top: 12.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(estimated ? 'Total (estimated)' : 'Grand total',
                      style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                Text(formatMoneyStr(totals['grand_total']),
                    style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
              ],
            ),
          ),
          for (final r in extra) MetaRow(label: r.$1, value: r.$2, last: r == extra.last),
          if (estimated) ...[
            SizedBox(height: 8.h),
            Text('Tax is recalculated when the invoice is issued.',
                style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          ],
        ],
      ),
    );
  }
}

/// A document's lines — description, HSN/SAC · rate, qty × price, taxable.
class AccLinesCard extends StatelessWidget {
  const AccLinesCard({super.key, required this.lines, this.title = 'Items'});

  final List<AccDocumentLine> lines;
  final String title;

  @override
  Widget build(BuildContext context) {
    return FinanceCard(
      title: title,
      child: Column(
        children: [
          if (lines.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              child: Text('No lines', style: AppText.caption()),
            ),
          for (int i = 0; i < lines.length; i++) _row(lines[i], i == lines.length - 1),
        ],
      ),
    );
  }

  Widget _row(AccDocumentLine l, bool last) {
    final meta = [
      if ((l.hsnSac ?? '').isNotEmpty) 'HSN ${l.hsnSac}',
      if ((l.ratePct ?? '').isNotEmpty) '${_trimPct(l.ratePct!)}%',
      if ((l.supplyNature ?? '').isNotEmpty) label(supplyNatureLabels, l.supplyNature),
    ].join(' · ');
    return Container(
      padding: EdgeInsets.symmetric(vertical: 11.h),
      decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.description.isEmpty ? 'Line ${l.lineNo}' : l.description,
                    style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                if (meta.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text(meta, style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                ],
                SizedBox(height: 2.h),
                Text('${_trimQty(l.qty)} × ${formatMoneyStr(l.unitPrice)}'
                    '${moneyIsZero(l.lineDiscount) ? '' : ' − ${formatMoneyStr(l.lineDiscount)}'}',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          Text(formatMoneyStr(l.taxable ?? _lineGross(l)),
              style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  /// A draft line has no server taxable yet; qty × price is a hint only.
  static String _lineGross(AccDocumentLine l) =>
      toMoneyStr(moneyNum(l.qty) * moneyNum(l.unitPrice) - moneyNum(l.lineDiscount));
}

String _trimQty(String q) {
  final v = double.tryParse(q);
  if (v == null) return q;
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

String _trimPct(String p) => _trimQty(p);

/// A label ⋯ value row whose value is money — keeps paise.
class MoneyRow extends StatelessWidget {
  const MoneyRow({super.key, required this.label, required this.value, this.last = false});
  final String label;
  final String? value;
  final bool last;

  @override
  Widget build(BuildContext context) => MetaRow(label: label, value: formatMoneyStr(value), last: last);
}

// ── Form pieces ──

/// A labelled money input: digits and one decimal point, 2 dp.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '0.00',
    this.required = false,
    this.onChanged,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool required;
  final ValueChanged<String>? onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) => AccInput(
        label: label,
        controller: controller,
        hint: hint,
        required: required,
        onChanged: onChanged,
        errorText: errorText,
        prefix: '₹',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
      );
}

/// The sheets' input box — label above, 44h, 11r, 1.5px border. The same
/// chrome as the Record payment sheet's fields.
class AccInput extends StatelessWidget {
  const AccInput({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '',
    this.required = false,
    this.onChanged,
    this.keyboardType,
    this.inputFormatters,
    this.prefix,
    this.errorText,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool required;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefix;
  final String? errorText;
  final int maxLines;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetFieldLabel(label, required: required),
        Container(
          constraints: BoxConstraints(minHeight: 44.h),
          padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: maxLines > 1 ? 10.h : 0),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(11.r),
            border: Border.all(color: errorText != null ? AppColors.error : AppColors.borderInput, width: 1.5),
          ),
          child: Row(
            children: [
              if (prefix != null) ...[
                Text(prefix!, style: AppText.body(color: AppColors.textMuted)),
                SizedBox(width: 6.w),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  textCapitalization: textCapitalization,
                  minLines: 1,
                  maxLines: maxLines,
                  style: AppText.body(),
                  cursorColor: AppColors.blueBright,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: AppText.body(color: AppColors.textPlaceholder),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (errorText != null) ...[
          SizedBox(height: 5.h),
          Text(errorText!, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.error)),
        ],
      ],
    );
  }
}

/// A tappable picker box (party, state, date, category…): shows [value] or the
/// [hint], with a trailing icon.
class AccPickerBox extends StatelessWidget {
  const AccPickerBox({
    super.key,
    required this.label,
    required this.onTap,
    this.value,
    this.hint = 'Select…',
    this.required = false,
    this.icon = PhosphorIconsBold.caretDown,
    this.enabled = true,
    this.footnote,
  });

  final String label;
  final VoidCallback onTap;
  final String? value;
  final String hint;
  final bool required;
  final IconData icon;
  final bool enabled;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final has = (value ?? '').isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetFieldLabel(label, required: required),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.6,
            child: Container(
              height: 46.h,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: enabled ? AppColors.white : AppColors.bgChipGrey,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: AppColors.borderInput, width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(has ? value! : hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: has ? AppText.body() : AppText.body(color: AppColors.textPlaceholder)),
                  ),
                  Icon(icon, size: 14.sp, color: AppColors.textPlaceholder),
                ],
              ),
            ),
          ),
        ),
        if (footnote != null) ...[
          SizedBox(height: 5.h),
          Text(footnote!, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
        ],
      ],
    );
  }
}

/// A date box. Dates are read by the backend in IST, which the footnote says —
/// a phone abroad would otherwise pick "today" in the wrong day.
class AccDateBox extends StatelessWidget {
  const AccDateBox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.clearable = false,
    this.showIstHint = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool required;
  final bool clearable;
  final bool showIstHint;

  @override
  Widget build(BuildContext context) {
    return AccPickerBox(
      label: label,
      required: required,
      value: value == null ? null : formatApiDay(isoDay(value!)),
      hint: clearable ? 'Not set' : 'Pick a date',
      icon: PhosphorIconsRegular.calendarBlank,
      footnote: showIstHint ? 'Dates are in IST' : null,
      onTap: () async {
        final picked = await pickSheetDate(context, value == null ? '' : isoDay(value!));
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// One-of-N chips in the sheets' select-chip style.
class AccChoiceChips extends StatelessWidget {
  const AccChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.label,
    this.required = false,
  });

  /// value → label, in display order.
  final Map<String, String> options;
  final String? selected;
  final ValueChanged<String> onSelected;
  final String? label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) SheetFieldLabel(label!, required: required),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final e in options.entries)
              SelectChip(label: e.value, selected: selected == e.key, onTap: () => onSelected(e.key)),
          ],
        ),
      ],
    );
  }
}

/// A checkbox row — the CRM check box beside a label and an optional hint.
class AccCheckRow extends StatelessWidget {
  const AccCheckRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CrmCheckBox(done: value, onTap: () => onChanged(!value), size: 22),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 2.h),
                  child: Text(label, style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
                ),
                if (hint != null) ...[
                  SizedBox(height: 2.h),
                  Text(hint!, style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A collapsible "More options" block inside a sheet.
class AccDisclosure extends StatefulWidget {
  const AccDisclosure({super.key, required this.title, required this.children, this.initiallyOpen = false});

  final String title;
  final List<Widget> children;
  final bool initiallyOpen;

  @override
  State<AccDisclosure> createState() => _AccDisclosureState();
}

class _AccDisclosureState extends State<AccDisclosure> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6.h),
            child: Row(
              children: [
                Text(widget.title, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
                SizedBox(width: 5.w),
                Icon(_open ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
                    size: 12.sp, color: AppColors.blueBright),
              ],
            ),
          ),
        ),
        if (_open) ...[
          SizedBox(height: 8.h),
          for (int i = 0; i < widget.children.length; i++) ...[
            if (i > 0) SizedBox(height: 13.h),
            widget.children[i],
          ],
        ],
      ],
    );
  }
}

/// The idempotency key to use after a failed post.
///
/// Kept only when the server may never have seen the request (no status —
/// a network error or a timeout), so a retry replays it and posts once. Once
/// the server has answered, that submission is over: resubmitting corrected
/// values under the same key is refused as `IDEMPOTENCY_PAYLOAD_MISMATCH`
/// (handover §5), so a fresh key is minted.
String nextEventId(String current, AppError e) => e.statusCode == null ? current : newEventId();

/// Whether the device can post right now. Posting sheets disable their submit
/// when offline and say so — a queued post could land in a period that has
/// since closed (plan rule 3).
bool isOnline(WidgetRef ref) => ref.watch(isOnlineProvider).valueOrNull ?? true;

/// The line under a disabled submit when offline.
class OfflineNote extends StatelessWidget {
  const OfflineNote({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 10.h),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.wifiSlash, size: 14.sp, color: AppColors.error),
            SizedBox(width: 6.w),
            Text('Posting needs a connection',
                style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.error)),
          ],
        ),
      );
}
