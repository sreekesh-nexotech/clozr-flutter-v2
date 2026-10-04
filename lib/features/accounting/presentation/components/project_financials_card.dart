import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/money_format.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/reports_providers.dart';
import 'acc_widgets.dart';

/// A project's money (plan §5.6), read live from
/// `reports/project-financials/{id}/` rather than the persisted `financials`
/// field, which nothing refreshes on its own (handover §12.13).
///
/// Renders nothing unless accounting is active and the user can read reports;
/// a failed read (404 = no figures yet) also renders nothing. No rederive on
/// mobile.
class ProjectFinancialsCard extends ConsumerWidget {
  const ProjectFinancialsCard({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(accountingActiveProvider) || !ref.watch(accPermProvider('acc_report')).read) {
      return const SizedBox.shrink();
    }
    final async = ref.watch(projectFinancialsProvider(projectId));
    if (async.hasError) return const SizedBox.shrink();
    final f = async.valueOrNull;
    if (f == null) {
      if (!async.isLoading) return const SizedBox.shrink();
      return FinanceCard(
        title: 'Financials',
        child: SizedBox(
          height: 48.h,
          child: const Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.navy)),
          ),
        ),
      );
    }
    return FinanceCard(
      title: 'Financials',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MoneyRow(label: 'Billed', value: f.billedGross),
          MoneyRow(label: 'Collected', value: f.collected),
          MoneyRow(label: 'Open receivable', value: f.openAr),
          MoneyRow(label: 'Purchases', value: f.purchaseTaxable),
          MoneyRow(label: 'Expenses', value: f.expenseTaxable),
          MoneyRow(label: 'Open payable', value: f.vendorOpenAp),
          Padding(
            padding: EdgeInsets.only(top: 12.h),
            child: Row(
              children: [
                Expanded(
                  child: Text('Gross margin',
                      style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                Text(formatMoneyStr(f.grossMargin),
                    style: AppText.custom(
                        size: 17,
                        weight: FontWeight.w800,
                        color: moneyNum(f.grossMargin) < 0 ? AppColors.error : AppColors.success)),
              ],
            ),
          ),
          if (f.asOfEntryNo != null) ...[
            SizedBox(height: 6.h),
            Text('As of entry ${f.asOfEntryNo}', style: AppText.micro()),
          ],
        ],
      ),
    );
  }
}
