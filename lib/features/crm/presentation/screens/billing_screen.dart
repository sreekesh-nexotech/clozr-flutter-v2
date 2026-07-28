import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../components/finance_widgets.dart';

/// Billing — the tenant's plan, seat/storage usage, payment mandate, account
/// state and GST invoice history. Values mirror the prototype's static
/// `billingVM`; every action fires an informational toast.
class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  static const _invoices = [
    ('INV-2026-06', '01 Jun 2026'),
    ('INV-2026-05', '01 May 2026'),
    ('INV-2026-04', '01 Apr 2026'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void toast(String m) => ref.read(toastProvider.notifier).show(m);

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            Text('Billing', style: AppText.screenTitle()),
          ],
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
            children: [
              _planCard(toast),
              SizedBox(height: 14.h),
              _licensesCard(toast),
              SizedBox(height: 14.h),
              _storageCard(),
              SizedBox(height: 14.h),
              _mandateCard(toast),
              SizedBox(height: 14.h),
              _accountStateCard(),
              SizedBox(height: 14.h),
              _invoicesCard(toast),
            ],
          ),
        ),
      ],
    );
  }

  Widget _planCard(void Function(String) toast) {
    return Container(
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(0.28), blurRadius: 26, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CURRENT PLAN',
              style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: const Color(0xFFB9C2D8), letterSpacing: 1)),
          SizedBox(height: 6.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Business', style: AppText.custom(size: 23, weight: FontWeight.w800, color: AppColors.white, letterSpacing: -0.4)),
                    SizedBox(height: 3.h),
                    Text('8 seats · billed monthly · renews 1 Jul 2026',
                        style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.white.withOpacity(0.66))),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  text: '₹48,000',
                  style: AppText.custom(size: 21, weight: FontWeight.w800, color: AppColors.white, letterSpacing: -0.4),
                  children: [
                    TextSpan(text: '/mo', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.white.withOpacity(0.6))),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 15.h),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => toast('Change plan — coming soon'),
                  child: Container(
                    height: 40.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10.r)),
                    child: Text('Change plan', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.navy)),
                  ),
                ),
              ),
              SizedBox(width: 9.w),
              GestureDetector(
                onTap: () => toast('Talk to support to cancel'),
                child: Container(
                  height: 40.h,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: AppColors.white.withOpacity(0.32), width: 1.5),
                  ),
                  child: Text('Cancel', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _licensesCard(void Function(String) toast) {
    return ClozrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('Licenses (seats)', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary))),
              Text('0 free to assign', style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
            ],
          ),
          SizedBox(height: 8.h),
          Text('8 / 8 used', style: AppText.custom(size: 21, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
          SizedBox(height: 10.h),
          _bar(1.0, AppColors.navy),
          SizedBox(height: 13.h),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => toast('License added — ₹6,000/mo prorated'),
                  child: Container(
                    height: 42.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.plus, size: 14.sp, color: AppColors.white),
                        SizedBox(width: 7.w),
                        Text('Add licenses', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.white)),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 9.w),
              Expanded(
                child: GestureDetector(
                  onTap: () => toast('All seats are currently assigned'),
                  child: Container(
                    height: 42.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(11.r),
                      border: Border.all(color: const Color(0xFFE6E7EA)),
                    ),
                    child: Text('Remove', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _storageCard() {
    return ClozrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Storage', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 8.h),
          Text('14 GB / 50 GB', style: AppText.custom(size: 21, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
          SizedBox(height: 10.h),
          _bar(0.28, _chartTeal),
          SizedBox(height: 10.h),
          Text('Per-tenant cap for the Business plan. Renews on day 1 each cycle.',
              style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder, height: 1.5)),
        ],
      ),
    );
  }

  Widget _mandateCard(void Function(String) toast) {
    return ClozrCard(
      child: Row(
        children: [
          const IconChip(icon: PhosphorIconsRegular.bank, size: 42, radius: 12, iconSize: 20),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment mandate · eNACH', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 2.h),
                Text('HDFC Bank ···· 4821 · Auto-pay authorized up to 10 seats',
                    style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: () => toast('Manage mandate — coming soon'),
            child: Text('Manage', style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.blueBright)),
          ),
        ],
      ),
    );
  }

  Widget _accountStateCard() {
    return ClozrCard(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Wrap(
        spacing: 10.w,
        runSpacing: 8.h,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsRegular.userCheck, size: 13.sp, color: AppColors.textMuted),
              SizedBox(width: 5.w),
              Text('Account state', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted)),
            ],
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(8.r)),
            child: Text('Active', style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.success)),
          ),
          Text('Place of supply: Karnataka (29) · Intra-state · CGST + SGST',
              style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
        ],
      ),
    );
  }

  Widget _invoicesCard(void Function(String) toast) {
    return ClozrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Invoices & billing history', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary))),
              Text('GST invoices · tap to view', style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
            ],
          ),
          SizedBox(height: 4.h),
          for (int i = 0; i < _invoices.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => toast('Opening GST invoice…'),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 12.h),
                decoration: i == _invoices.length - 1
                    ? null
                    : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_invoices[i].$1, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                          SizedBox(height: 2.h),
                          Text('Business · 8 seats · monthly · ${_invoices[i].$2}',
                              style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
                      decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(8.r)),
                      child: Text('Paid', style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.success)),
                    ),
                    SizedBox(width: 10.w),
                    Text('₹56,640', style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(double factor, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9999.r),
      child: Container(
        height: 8.h,
        color: AppColors.borderCardSoft,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: factor,
          child: Container(color: color),
        ),
      ),
    );
  }
}

/// The prototype's `#3AA0B8` chart teal (storage bar / funnel gradient) — no
/// design token exists for it.
const Color _chartTeal = Color(0xFF3AA0B8);
