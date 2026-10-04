import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../application/providers/accounting_providers.dart';
import '../components/acc_widgets.dart';

/// Reports (plan §4.12) — the picker. Each card opens one report; GST, TDS
/// and ITC live on the Periods screen, statements on the party pages.
class AccReportsScreen extends ConsumerWidget {
  const AccReportsScreen({super.key});

  static const _reports = <(String, IconData, String, String)>[
    ('ar_aging', PhosphorIconsRegular.arrowCircleDown, 'Receivable aging', 'Who owes you, and for how long'),
    ('ap_aging', PhosphorIconsRegular.arrowCircleUp, 'Payable aging', 'What you owe vendors, by age'),
    ('pnl', PhosphorIconsRegular.chartLineUp, 'Profit & loss', 'Income, expenses and net profit'),
    ('balance_sheet', PhosphorIconsRegular.scales, 'Balance sheet', 'Assets, liabilities and equity'),
    ('trial_balance', PhosphorIconsRegular.listNumbers, 'Trial balance', 'Every account’s closing balance'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canRead = ref.watch(accPermProvider('acc_report')).read;
    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(section: 'Reports', onBack: () => context.pop()),
          Expanded(
            child: AccountingGate(
              child: !canRead
                  ? ListView(children: const [
                      EmptyState(
                        icon: PhosphorIconsRegular.lock,
                        title: 'No access',
                        body: 'Your role cannot see accounting reports.',
                      ),
                    ])
                  : ListView(
                      padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 32.h),
                      children: [
                        for (final r in _reports) ...[
                          _card(context, r),
                          SizedBox(height: 10.h),
                        ],
                        SizedBox(height: 4.h),
                        const AccInfoBanner(
                          'Customer and vendor statements open from each customer or vendor page. '
                          'GST, TDS and ITC summaries are on the Periods screen.',
                        ),
                        SizedBox(height: 10.h),
                        GestureDetector(
                          onTap: () => context.push(Routes.accPeriods),
                          child: Text('Open Periods',
                              style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, (String, IconData, String, String) r) {
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: () => context.push('${Routes.accReport}?kind=${r.$1}'),
      child: Row(
        children: [
          IconChip(icon: r.$2),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.$3, style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 3.h),
                Text(r.$4, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
          Icon(PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.textPlaceholder),
        ],
      ),
    );
  }
}
