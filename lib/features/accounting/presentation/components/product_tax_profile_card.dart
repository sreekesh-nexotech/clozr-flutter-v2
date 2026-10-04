import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_masters.dart';
import '../config/accounting_copy.dart';
import '../sheets/acc_sheet_scaffold.dart';
import 'acc_widgets.dart';

/// A product's accounting tax defaults (plan §5.4, handover §8.2): the default
/// treatment, reverse charge on sales, cess, and the rate variant pinned from
/// an invoice preview. Renders nothing unless accounting is active and the
/// role can read setup.
///
/// The variant is read-only here on purpose — it is only ever set by picking
/// among the candidates an issue offers, where the choice has context.
class ProductTaxProfileCard extends ConsumerWidget {
  const ProductTaxProfileCard({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(accountingActiveProvider) || !ref.watch(accPermProvider('acc_setup')).read) {
      return const SizedBox.shrink();
    }
    final async = ref.watch(productTaxProfileProvider(productId));
    final p = async.valueOrNull;
    if (p == null) return const SizedBox.shrink();
    final canEdit = ref.watch(accPermProvider('acc_setup')).update;
    return Padding(
      padding: EdgeInsets.only(top: 14.h),
      child: FinanceCard(
        title: 'Tax profile',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!p.exists)
              Padding(
                padding: EdgeInsets.only(top: 4.h, bottom: 6.h),
                child: Text('No tax profile yet — invoices use the rate for the product\'s HSN/SAC.',
                    style: AppText.body(color: AppColors.textMuted)),
              )
            else ...[
              MetaRow(label: 'Default treatment', value: label(taxTreatmentLabels, p.taxTreatmentDefault)),
              MetaRow(label: 'Reverse charge on sales', value: p.isRcmOutward ? 'Yes' : 'No'),
              MetaRow(label: 'Cess applies', value: p.cessApplicable ? 'Yes' : 'No'),
              MetaRow(
                label: 'Pinned rate variant',
                value: p.rateVariantKey ?? 'None — set from an invoice preview',
                last: true,
              ),
            ],
            if (canEdit) ...[
              SizedBox(height: 10.h),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showClozrSheet<void>(
                  context: context,
                  builder: (_) => _ProductTaxSheet(productId: productId, profile: p),
                ),
                child: Row(
                  children: [
                    Icon(PhosphorIconsRegular.pencilSimple, size: 15.sp, color: AppColors.blueBright),
                    SizedBox(width: 6.w),
                    Text(p.exists ? 'Edit tax profile' : 'Set up tax profile',
                        style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductTaxSheet extends ConsumerStatefulWidget {
  const _ProductTaxSheet({required this.productId, required this.profile});
  final String productId;
  final ProductTaxProfile profile;

  @override
  ConsumerState<_ProductTaxSheet> createState() => _ProductTaxSheetState();
}

class _ProductTaxSheetState extends ConsumerState<_ProductTaxSheet> {
  late String _treatment = widget.profile.taxTreatmentDefault ?? 'TAXABLE';
  late bool _rcm = widget.profile.isRcmOutward;
  late bool _cess = widget.profile.cessApplicable;
  bool _busy = false;
  AppError? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountingRepositoryProvider).saveProductTaxProfile(widget.productId, {
        'tax_treatment_default': _treatment,
        // Kept as it is: only an invoice preview's candidate list sets it.
        if (widget.profile.rateVariantKey != null) 'rate_variant_key': widget.profile.rateVariantKey,
        'is_rcm_outward': _rcm,
        'cess_applicable': _cess,
      });
      ref.invalidate(productTaxProfileProvider(widget.productId));
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Tax profile saved');
      Navigator.of(context).pop();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccSheetScaffold(
      title: 'Tax profile',
      submitLabel: 'Save',
      busyLabel: 'Saving…',
      posts: false,
      busy: _busy,
      error: _error,
      onSubmit: _save,
      children: [
        AccChoiceChips(
          label: 'Default treatment',
          options: const {'TAXABLE': 'Taxable', 'NIL': 'Nil rated', 'EXEMPT': 'Exempt', 'NON_GST': 'Non-GST'},
          selected: _treatment,
          onSelected: (v) => setState(() => _treatment = v),
        ),
        AccCheckRow(
          label: 'Reverse charge on sales',
          hint: 'The buyer pays the GST on this product.',
          value: _rcm,
          onChanged: (v) => setState(() => _rcm = v),
        ),
        AccCheckRow(label: 'Cess applies', value: _cess, onChanged: (v) => setState(() => _cess = v)),
      ],
    );
  }
}
