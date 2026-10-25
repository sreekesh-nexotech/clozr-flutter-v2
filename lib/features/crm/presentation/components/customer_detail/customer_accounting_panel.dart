import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../accounting/application/providers/accounting_providers.dart';
import '../../../../accounting/presentation/components/customer_accounting.dart';
import '../../../../accounting/presentation/sheets/party_tax_profile_sheet.dart';

/// Webapp `CustomerAccountingPanel` gating: shown only while accounting is
/// active, and only when the role holds at least one of `acc_document`
/// (Invoices), `acc_settlement` (Receipts, Advances & credits) or `acc_setup`
/// (Tax profile). Hidden entirely otherwise.
bool showCustomerAccountingPanel({
  required bool accountingActive,
  required bool canDocs,
  required bool canSettle,
  required bool canSetup,
}) =>
    accountingActive && (canDocs || canSettle || canSetup);

/// The customer's accounting card, below the notes as on the webapp.
class CustomerAccountingPanel extends ConsumerWidget {
  const CustomerAccountingPanel({super.key, required this.customerId, required this.customerName});

  final String customerId;
  final String customerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSetup = ref.watch(accPermProvider('acc_setup')).read;
    final show = showCustomerAccountingPanel(
      accountingActive: ref.watch(accountingActiveProvider),
      canDocs: ref.watch(accPermProvider('acc_document')).read,
      canSettle: ref.watch(accPermProvider('acc_settlement')).read,
      canSetup: canSetup,
    );
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: ClozrCard(
        radius: 18,
        padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 12.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accounting', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            CustomerAccountingTab(customerId: customerId),
            if (canSetup) ...[
              SizedBox(height: 12.h),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showPartyTaxProfileSheet(context, kind: 'customer', partyId: customerId, title: customerName),
                child: Row(
                  children: [
                    Icon(PhosphorIconsRegular.identificationCard, size: 16.sp, color: AppColors.blueBright),
                    SizedBox(width: 6.w),
                    Text('Tax profile',
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
