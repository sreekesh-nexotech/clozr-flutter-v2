import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../data/mock/mock_users.dart';
import '../../domain/entities/ticket.dart';
import '../util/ticket_sla.dart';

/// A minimal, read-only Support Overview row: muted ticket id, truncated
/// subject, an optional linked-task glyph, the SLA pill, a priority dot and the
/// primary assignee avatar. No drag affordances.
class BoardRow extends StatelessWidget {
  const BoardRow({super.key, required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pill = boardPill(ticket);
    // Null when nobody is on the ticket. It used to fall back to `'me'`, so an
    // unassigned ticket wore the signed-in user's initials and read as theirs.
    final rep = ticket.assignees.isEmpty ? null : MockUsers.of(ticket.assignees.first);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
        child: Row(
          children: [
            // `displayRef` ("TKT-0025"), never `id` — that is the `issue_id`
            // uuid, and 36 characters of it pushed the rest of the row off the
            // right edge. Every other ticket surface already uses this.
            //
            // Capped as well: `displayRef` falls back to the uuid when a row
            // carries no `reference`, and this Text sits outside the Expanded,
            // so anything long would overflow rather than truncate.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 92.w),
              child: Text(ticket.displayRef,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(ticket.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            if (ticket.taskId != null) ...[
              SizedBox(width: 8.w),
              Icon(PhosphorIconsRegular.linkSimple, size: 13.sp, color: AppColors.textPlaceholder),
            ],
            SizedBox(width: 8.w),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
              decoration: BoxDecoration(color: pill.bg, borderRadius: BorderRadius.circular(7.r)),
              child: Text(pill.label, style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: pill.fg)),
            ),
            SizedBox(width: 8.w),
            Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: ticketPriDotColor(ticket.pri), shape: BoxShape.circle)),
            SizedBox(width: 8.w),
            Container(
              width: 19.w,
              height: 19.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rep?.color ?? AppColors.bgChipGrey,
                shape: BoxShape.circle,
              ),
              child: rep == null
                  // An empty slot keeps the row's alignment while saying, truthfully,
                  // that nobody is on it.
                  ? Icon(PhosphorIconsRegular.user, size: 10.sp, color: AppColors.textPlaceholder)
                  : Text(rep.initials,
                      style: AppText.custom(size: 8.5, weight: FontWeight.w700, color: AppColors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
