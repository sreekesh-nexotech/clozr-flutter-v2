import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../application/dash_navigation.dart';
import '../../../application/providers/dashboard_providers.dart';
import '../../../domain/entities/dash_colors.dart';
import '../../../domain/entities/dashboard_models.dart';
import '../dash_kpi_card.dart';

/// The Business / admin dashboard panel (period chip only): KPIs, a total
/// receivables breakdown (aging + upcoming), top-5 outstanding and top
/// customers.
class BusinessPanel extends ConsumerWidget {
  const BusinessPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardDataProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashKpiGrid(
            kpis: data.adminKpis,
            // A period figure's link gets the period (`period=1` → from/to).
            onTapKpi: (k) =>
                dashGo(context, ref, dashPeriodLink(ref, k.route))),
        SizedBox(height: 16.h),
        _receivables(data),
        SizedBox(height: 16.h),
        _outstanding(context, ref, data),
        SizedBox(height: 16.h),
        _topCustomers(context, ref, data),
      ],
    );
  }

  Widget _receivables(DashboardData d) {
    return ClozrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total receivables',
                        style: AppText.custom(
                            size: 15,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text("What's overdue + what's coming in",
                        style: AppText.custom(
                            size: 12,
                            weight: FontWeight.w500,
                            color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              // Shares the row with the title instead of taking whatever the
              // sub-line needs, so at a large font the title wraps between
              // words rather than inside "receivables".
              Flexible(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(d.receivablesTotal,
                        style: AppText.custom(
                            size: 20,
                            weight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.4)),
                    SizedBox(height: 1.h),
                    Text(d.receivablesSub,
                        textAlign: TextAlign.end,
                        style: AppText.custom(
                            size: 10.5,
                            weight: FontWeight.w600,
                            color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
            ],
          ),
          _divider(),
          Text(d.overdueTotal,
              style: AppText.custom(
                  size: 13, weight: FontWeight.w700, color: DashColors.red)),
          SizedBox(height: 10.h),
          _agingBar(d.aging),
          SizedBox(height: 6.h),
          _twoColGrid([
            for (final a in d.aging) _agingCell(a),
          ]),
          _divider(),
          Text(d.upcomingTotal,
              style: AppText.custom(
                  size: 13, weight: FontWeight.w700, color: DashColors.green)),
          SizedBox(height: 2.h),
          _twoColGrid([
            for (final u in d.upcoming) _labelAmtCell(u),
          ]),
        ],
      ),
    );
  }

  /// The shared empty state for a Business card that has nothing to list: a
  /// soft glyph disc over a bold line and a quiet hint (webapp `DashEmpty`).
  Widget _empty(String title, String hint, {bool positive = false}) {
    final tone = positive ? DashColors.green : DashColors.textMid;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 24.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 40.w,
              decoration: BoxDecoration(
                  color: tone.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(
                  positive
                      ? PhosphorIconsFill.checkCircle
                      : PhosphorIconsRegular.buildings,
                  size: 20.sp,
                  color: tone),
            ),
            SizedBox(height: 10.h),
            Text(title,
                textAlign: TextAlign.center,
                style: AppText.custom(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            SizedBox(height: 2.h),
            Text(hint,
                textAlign: TextAlign.center,
                style: AppText.custom(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.textPlaceholder)),
          ],
        ),
      ),
    );
  }

  Widget _agingBar(List<DashAgingRow> rows) {
    // Nothing overdue: an empty track instead of zero-width segments.
    if (rows.every((r) => (r.pct * 10).round() <= 0)) {
      return Container(
        height: 8.h,
        decoration: BoxDecoration(
            color: DashColors.track,
            borderRadius: BorderRadius.circular(999.r)),
      );
    }
    return SizedBox(
      height: 8.h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999.r),
        child: Row(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(width: 3.w),
              Expanded(
                flex: (rows[i].pct * 10).round(),
                child: Container(color: rows[i].color),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _agingCell(DashAgingRow a) {
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: Row(
        children: [
          Container(
              width: 9.w,
              height: 9.w,
              decoration:
                  BoxDecoration(color: a.color, shape: BoxShape.circle)),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.label,
                    style: AppText.custom(
                        size: 11.5,
                        weight: FontWeight.w500,
                        color: AppColors.textMuted)),
                Text(a.amt,
                    style: AppText.custom(
                        size: 13.5,
                        weight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelAmtCell(DashLabelAmt u) {
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(u.label,
              style: AppText.custom(
                  size: 11.5,
                  weight: FontWeight.w500,
                  color: AppColors.textMuted)),
          Text(u.amt,
              style: AppText.custom(
                  size: 13.5,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _twoColGrid(List<Widget> cells) {
    return Column(
      children: [
        for (int r = 0; r < cells.length; r += 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cells[r]),
              SizedBox(width: 14.w),
              Expanded(
                  child:
                      (r + 1) < cells.length ? cells[r + 1] : const SizedBox()),
            ],
          ),
      ],
    );
  }

  Widget _outstanding(BuildContext context, WidgetRef ref, DashboardData d) {
    return ClozrCard(
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 8.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text('Top 5 outstanding',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              SizedBox(width: 8.w),
              Text(d.outstandingTotal,
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w700,
                      color: DashColors.blue)),
            ],
          ),
          SizedBox(height: 4.h),
          if (d.outstanding.isEmpty)
            _empty('No outstanding dues', 'Every customer is settled up.',
                positive: true)
          else
            for (final o in d.outstanding) _outstandingRow(context, ref, o),
        ],
      ),
    );
  }

  Widget _outstandingRow(
      BuildContext context, WidgetRef ref, DashOutstanding o) {
    final daysColor = o.days > 60 ? DashColors.red : DashColors.amberDeep;
    // Their overdue payments — the rows that sum to the amount shown.
    return _customerTap(
        context,
        ref,
        o.id,
        link: o.name.trim().isEmpty
            ? null
            : '${Routes.payments}?mode=payments&tab=overdue'
                '&cust=${Uri.encodeQueryComponent(o.name)}',
        Container(
          padding: EdgeInsets.symmetric(vertical: 11.h),
          decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: AppColors.bgLight, width: 1))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(o.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(
                            size: 13.5,
                            weight: FontWeight.w600,
                            color: AppColors.textBody)),
                  ),
                  SizedBox(width: 9.w),
                  Text('${o.days}d',
                      style: AppText.custom(
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: daysColor)),
                  SizedBox(width: 9.w),
                  Text(o.amt,
                      style: AppText.custom(
                          size: 13,
                          weight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
              SizedBox(height: 8.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(999.r),
                child: LinearProgressIndicator(
                  value: (o.pct / 100).clamp(0.0, 1.0),
                  minHeight: 6.h,
                  backgroundColor: DashColors.track,
                  valueColor: AlwaysStoppedAnimation(o.barColor),
                ),
              ),
            ],
          ),
        ));
  }

  Widget _topCustomers(BuildContext context, WidgetRef ref, DashboardData d) {
    return ClozrCard(
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 8.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text('Top customers',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                    color: DashColors.badgeGrey,
                    borderRadius: BorderRadius.circular(8.r)),
                child: Text('₹ Value',
                    style: AppText.custom(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.navy)),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          if (d.topCustomers.isEmpty)
            _empty('No customer activity',
                'No customers recorded revenue or dues in this period.'),
          for (final c in d.topCustomers)
            _customerTap(
                context,
                ref,
                c.id,
                // Their payment plans (the ₹ value sums the unpaid ones).
                link: c.name.trim().isEmpty
                    ? null
                    : '${Routes.payments}?mode=invoices'
                        '&cust=${Uri.encodeQueryComponent(c.name)}',
                Container(
                  padding: EdgeInsets.symmetric(vertical: 11.h),
                  decoration: const BoxDecoration(
                      border: Border(
                          bottom:
                              BorderSide(color: AppColors.bgLight, width: 1))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            SizedBox(height: 1.h),
                            Text(c.sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(
                                    size: 11.5,
                                    weight: FontWeight.w500,
                                    color: AppColors.textPlaceholder)),
                          ],
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Text(c.amt,
                          style: AppText.custom(
                              size: 14,
                              weight: FontWeight.w800,
                              color: DashColors.green)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  /// Wraps a customer row so a tap opens that customer; rows the API sent
  /// without an id stay inert.
  /// [link] is the list the row's figure comes from (Payments filtered to the
  /// customer); without one, the customer record. Rows the API sent without
  /// an id or name stay inert.
  Widget _customerTap(
      BuildContext context, WidgetRef ref, String id, Widget row,
      {String? link}) {
    final target =
        link ?? (id.isEmpty ? '' : '${Routes.customerDetail}?id=$id');
    if (target.isEmpty) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => dashGo(context, ref, target),
      child: row,
    );
  }

  Widget _divider() => Container(
        margin: EdgeInsets.symmetric(vertical: 14.h),
        height: 1,
        color: AppColors.borderCardSoft,
      );
}
