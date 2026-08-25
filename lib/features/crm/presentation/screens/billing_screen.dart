import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/utils/inr_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/billing_providers.dart';
import '../../domain/entities/billing.dart';
import '../components/finance_widgets.dart';

/// Billing — the tenant's plan, seat/storage usage, payment mandate, account
/// state and GST invoice history. Values mirror the prototype's static
/// `billingVM`; every action fires an informational toast.
class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

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
          // In API mode only the cards with an endpoint behind them are shown:
          // storage, invoice history and the plans list. The plan header,
          // seats, mandate and account-state cards are still the prototype's
          // static figures — there is no subscription endpoint to fill them —
          // so they stay out rather than being dressed up as real.
          //
          // This used to be a blanket "Billing coming soon" for the whole
          // screen, which hid the three collections that do answer.
          child: ApiConfig.apiEnabled
              ? ListView(
                  padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                  children: [
                    _storageCard(ref),
                    SizedBox(height: 14.h),
                    _invoicesCard(ref, toast),
                    SizedBox(height: 14.h),
                    _plansCard(context, ref, toast),
                    SizedBox(height: 14.h),
                    _pendingCard(),
                  ],
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                  children: [
                    _planCard(context, ref, toast),
                    SizedBox(height: 14.h),
                    _licensesCard(toast),
                    SizedBox(height: 14.h),
                    _storageCard(ref),
                    SizedBox(height: 14.h),
                    _mandateCard(toast),
                    SizedBox(height: 14.h),
                    _accountStateCard(),
                    SizedBox(height: 14.h),
                    _invoicesCard(ref, toast),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _planCard(BuildContext context, WidgetRef ref, void Function(String) toast) {
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
                  onTap: () => _openPlans(context, ref, toast),
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

  /// `GET /billing/storage/`.
  ///
  /// This card read "14 GB / 50 GB" with a 28%-full bar on every org. The dev
  /// org is on an **unlimited** plan using 8.88 MB, so both halves of that
  /// fraction and the bar were invented.
  Widget _storageCard(WidgetRef ref) {
    final usage = ref.watch(billingStorageProvider).valueOrNull;
    final headline = usage?.headline ?? '—';
    return ClozrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Storage', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 8.h),
          Text(headline, style: AppText.custom(size: 21, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
          SizedBox(height: 10.h),
          // No cap, no fraction: a full bar under "unlimited" would read as a
          // quota about to run out.
          if (usage == null || !usage.unlimited) ...[
            _bar(usage?.fraction ?? 0, _chartTeal),
            SizedBox(height: 10.h),
          ],
          Text(
              usage == null
                  ? 'Files uploaded across the workspace.'
                  : usage.unlimited
                      ? 'Files uploaded across the workspace. This plan has no storage cap.'
                      : 'Files uploaded across the workspace, against your plan’s cap.',
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

  /// `GET /billing/invoices/` — real invoice numbers, periods, statuses and
  /// totals. Every row used to read "Business · 8 seats · monthly", "Paid" and
  /// "₹56,640", whatever the invoice actually was.
  Widget _invoicesCard(WidgetRef ref, void Function(String) toast) {
    final async = ref.watch(billingInvoicesProvider);
    final invoices = async.valueOrNull ?? const <BillingInvoice>[];
    if (invoices.isEmpty) {
      return ClozrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invoices & billing history',
                style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            SizedBox(height: 10.h),
            Text(
                async.isLoading
                    ? 'Loading invoices…'
                    : 'No invoices yet. They appear here once a billing cycle closes.',
                style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          ],
        ),
      );
    }
    return ClozrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Invoices & billing history', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary))),
              Text('${invoices.length} invoice${invoices.length == 1 ? '' : 's'}',
                  style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
            ],
          ),
          SizedBox(height: 4.h),
          for (int i = 0; i < invoices.length; i++)
            _invoiceRow(invoices[i], last: i == invoices.length - 1, toast: toast),
        ],
      ),
    );
  }

  /// One invoice row. The status pill shows the server's own word, and an
  /// invoice with money still due is coloured by that rather than by the word.
  Widget _invoiceRow(BillingInvoice inv, {required bool last, required void Function(String) toast}) {
    final paid = inv.isPaid && !inv.isOutstanding;
    final label = inv.status.isEmpty
        ? '—'
        : inv.status[0].toUpperCase() + inv.status.substring(1);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // No document endpoint exists yet — saying so beats a spinner that ends
      // nowhere.
      onTap: () => toast('This invoice has no downloadable copy yet.'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: last
            ? null
            : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inv.number,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(_invoiceSubtitle(inv),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
              decoration: BoxDecoration(
                  color: paid ? AppColors.tintGreen : AppColors.tintAmber,
                  borderRadius: BorderRadius.circular(8.r)),
              child: Text(label,
                  style: AppText.custom(
                      size: 11.5,
                      weight: FontWeight.w700,
                      color: paid ? AppColors.success : AppColors.warningDeep)),
            ),
            SizedBox(width: 10.w),
            Text(formatInr(inv.total),
                style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  /// The billing period, and what is still owed when anything is.
  String _invoiceSubtitle(BillingInvoice inv) {
    final parts = <String>[];
    final from = inv.periodStart, to = inv.periodEnd;
    if (from != null && to != null) {
      parts.add('${absoluteDate(from)} – ${absoluteDate(to)}');
    } else if (inv.dueDate != null) {
      parts.add('Due ${absoluteDate(inv.dueDate)}');
    }
    if (inv.isOutstanding) parts.add('${formatInr(inv.amountDue)} due');
    return parts.join(' · ');
  }

  /// The entry point to the plans sheet.
  ///
  /// Deliberately not the prototype's plan header: that card states a plan
  /// name, a seat count, a renewal date and a monthly total, none of which any
  /// endpoint reports. This says only what can be known — that the plans exist
  /// and can be read.
  Widget _plansCard(
      BuildContext context, WidgetRef ref, void Function(String) toast) {
    final plans = ref.watch(billingPlansProvider).valueOrNull ?? const [];
    return ClozrCard(
      onTap: () => _openPlans(context, ref, toast),
      child: Row(
        children: [
          const IconChip(
              icon: PhosphorIconsRegular.creditCard, size: 42, radius: 12, iconSize: 20),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plans',
                    style: AppText.custom(
                        size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 2.h),
                Text(
                    plans.isEmpty
                        ? 'See what each plan includes'
                        : '${plans.length} plans · from ${formatInr(plans.first.monthlyPerUser)}/user/mo',
                    style: AppText.custom(
                        size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ],
            ),
          ),
          Icon(PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.textPlaceholder),
        ],
      ),
    );
  }

  /// What billing still cannot show, and why — so the gaps read as known rather
  /// than broken.
  Widget _pendingCard() {
    return ClozrCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.info, size: 16.sp, color: AppColors.textPlaceholder),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
                'Your current plan, seats and payment mandate are managed by support — '
                'the app cannot read or change them yet.',
                style: AppText.custom(
                    size: 12, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.5)),
          ),
        ],
      ),
    );
  }

  /// `GET /billing/plans/` — what the org can move to.
  ///
  /// Read-only on purpose: there is no subscription endpoint to write a change
  /// to (`/billing/subscription/` and `/billing/mandate/` both 404), so the
  /// sheet shows the real plans and their prices and says who to ask. Listing
  /// them beats "Change plan — coming soon", which told the user nothing about
  /// what they are on or could have.
  Future<void> _openPlans(
      BuildContext context, WidgetRef ref, void Function(String) toast) async {
    final plans = await ref.read(billingPlansProvider.future);
    if (!context.mounted) return;
    if (plans.isEmpty) {
      toast('Plans are unavailable right now.');
      return;
    }
    await showClozrSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(title: 'Plans'),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [for (final p in plans) _planRow(p)],
              ),
            ),
            SizedBox(height: 12.h),
            Text(
                'Changing your plan is handled by support — the app cannot switch it yet.',
                style: AppText.custom(
                    size: 12, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _planRow(BillingPlan plan) {
    final modules = plan.enabledModules;
    final sub = [
      if (plan.userLimitLabel case final l?) l,
      if (modules.isNotEmpty) '${modules.length} modules',
    ].join(' · ');
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.name,
                    style: AppText.custom(
                        size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              Text('${formatInr(plan.monthlyPerUser)}/user/mo',
                  style: AppText.custom(
                      size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          if (plan.description.isNotEmpty) ...[
            SizedBox(height: 3.h),
            Text(plan.description,
                style: AppText.custom(
                    size: 12, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.4)),
          ],
          if (sub.isNotEmpty) ...[
            SizedBox(height: 5.h),
            Text(sub,
                style: AppText.custom(
                    size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
          ],
          SizedBox(height: 3.h),
          Text('${formatInr(plan.annualPerUser)}/user billed annually',
              style: AppText.custom(
                  size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
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
