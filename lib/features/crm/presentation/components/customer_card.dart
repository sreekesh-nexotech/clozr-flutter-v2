import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/customers_columns.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/view_schema.dart';

/// The Customers list card — mirrors the lead card: rounded-square avatar,
/// name/company/project on the left, status pill / value / time on the right,
/// then a team-avatar row and a call button below a hairline.
///
/// The layout is **org-configurable**: [schema] says which of those slots the
/// org shows on its mobile card (`/crm/customers/schema/?view_type=mobile`). An
/// empty schema means "no opinion" and every slot renders, so mock mode and a
/// failed fetch look exactly as they did before this became configurable.
///
/// `name` is never gated — it is the module's protected anchor field, and the
/// avatar is derived from it. Nor is the Call button: it is an action, not a
/// column the schema has any say over.
class CustomerCard extends StatelessWidget {
  const CustomerCard({
    super.key,
    required this.customer,
    required this.onTap,
    required this.onCall,
    this.schema = ViewSchema.empty,
  });

  final Customer customer;
  final VoidCallback onTap;
  final VoidCallback onCall;

  /// The org's configured column set for the mobile card.
  final ViewSchema schema;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.customer[customer.status] ?? StatusMeta$.customer['active']!;
    final teamIds = customer.team.take(2).toList();
    final more = customer.team.length - teamIds.length;

    // Column names as the live schema reports them. `value_need` backs both the
    // need line and the amount, which the card splits across two slots.
    //
    // The company slot is `organization_name` — **not** `company_name`, which is
    // not a column on this model at all. Keying it wrongly meant the line was
    // hidden against every non-empty schema.
    // Also requires a value: `organization_name` is visible on the `mobile`
    // schema but trimmed out of the list payload (the data endpoint resolves its
    // view type from the request action, so it honours the org's `list` config).
    // On a card an empty value means "skip the slot", not "render a blank line".
    final showCompany = schema.shows('organization_name') &&
        (customer.company?.trim().isNotEmpty ?? false);
    final showProject = schema.showsAny(const ['value_need', 'purpose']);
    final showStatus = schema.shows('status');
    final showValue = schema.shows('value_need');
    // Whichever timestamp the org exposed. `created_at` belongs here too: it is
    // seeded visible ("Created On") while `activity` and `last_followup_at` are
    // hidden by default, so gating on activity alone left the card with no date
    // even though the org had asked for one.
    final showActivity = schema.showsAny(const ['activity', 'last_followup_at']);
    final showCreated = schema.showsAny(const ['created_at', 'status_entered_at']);
    final showTime = showActivity || showCreated;
    final showAssignees = schema.shows('assignees');
    // The right-hand column and the footer both collapse when nothing in them
    // is visible — otherwise they render as empty space and a stray hairline.
    final showSideColumn = showStatus || showValue || showTime;
    // Everything else the org made visible — `email`, `address`,
    // `assigned_team`, a custom column — as chips, in the org's order. Without
    // this the card could only render the six slots it was built with, so a
    // configured field arrived in the payload and was drawn by nothing.
    final extras = customerExtraColumns(customer, schema);

    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 62.w,
                  height: 62.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(15.r)),
                  child: Text(customer.initials,
                      style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.navy, letterSpacing: 0.4)),
                ),
                SizedBox(width: 13.w),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(customer.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.textPrimary)),
                            if (showCompany) ...[
                              SizedBox(height: 4.h),
                              Text(customer.company ?? '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body(color: AppColors.textMuted2)),
                            ],
                            if (showProject) ...[
                              SizedBox(height: 3.h),
                              Text(customer.project,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                            ],
                          ],
                        ),
                      ),
                      if (showSideColumn) ...[
                        SizedBox(width: 8.w),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (showStatus) StatusPill.meta(meta),
                            if (showValue) ...[
                              SizedBox(height: 5.h),
                              Text(customer.value,
                                  style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                            ],
                            if (showTime) ...[
                              SizedBox(height: 5.h),
                              // The relative "activity" stamp when the org shows
                              // it, the absolute created date otherwise — the two
                              // are different columns and only one may be visible.
                              Text(showActivity ? customer.time : customer.createdOn,
                                  style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (extras.isNotEmpty) ...[
            SizedBox(height: 12.h),
            Wrap(
              spacing: 6.w,
              runSpacing: 6.h,
              children: [for (final e in extras) _chip(e.label, e.value)],
            ),
          ],
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Row(
            children: [
              if (showAssignees) ...[
                AvatarStack(
                  size: 26,
                  items: [for (final id in teamIds) (MockUsers.of(id).initials, MockUsers.of(id).color)],
                ),
                SizedBox(width: 9.w),
                Text(more > 0 ? '+$more more' : 'Team',
                    style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
              const Spacer(),
              // Compact fixed-size Call button — matches the Leads card (#5).
              GestureDetector(
                onTap: onCall,
                child: Container(
                  width: 52.w,
                  height: 48.h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.blueCta, borderRadius: BorderRadius.circular(12.r)),
                  child: Icon(PhosphorIconsFill.phone, size: 19.sp, color: AppColors.navy),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: AppColors.bgChipGrey,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
            text: '$label ',
            style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textMuted),
          ),
          TextSpan(
            text: value,
            style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        ]),
      ),
    );
  }
}
