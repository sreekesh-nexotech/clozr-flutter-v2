import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/tickets_providers.dart';
import '../../domain/entities/ticket.dart';
import '../util/ticket_sla.dart';

/// The Tickets list card: subject (+ linked-task glyph), id · category and
/// customer on the left; status + priority pills on the right; an assignee
/// avatar stack and the SLA pill below a hairline.
class TicketCard extends ConsumerWidget {
  const TicketCard({super.key, required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = StatusMeta$.ticket[ticket.status] ?? StatusMeta$.ticket['new']!;
    final cust = ref.watch(ticketDirectoryProvider).customer(ticket.custId);
    final ids = ticket.assignees.take(2).toList();
    final more = ticket.assignees.length - ids.length;

    return ClozrCard(
      radius: 16,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(ticket.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 15.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        ),
                        if (ticket.taskId != null) ...[
                          SizedBox(width: 6.w),
                          Icon(PhosphorIconsRegular.linkSimple, size: 13.sp, color: AppColors.textPlaceholder),
                        ],
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text('${ticket.displayRef} · ${ticket.cat}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 2.h),
                    Text(cust?.display ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusPill.meta(meta),
                  SizedBox(height: 5.h),
                  StatusPill(label: ticket.pri, color: ticketPriPillColor(ticket.pri)),
                ],
              ),
            ],
          ),
          SizedBox(height: 11.h),
          Container(
            padding: EdgeInsets.only(top: 11.h),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.bgLight)),
            ),
            child: Row(
              children: [
                _avatars(ids, more),
                const Spacer(),
                TicketSlaPill(chip: ticketListSlaChip(ticket)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Overlapping assignee avatars.
  ///
  /// A [Stack], not a negative margin — `Container` asserts on one, so this
  /// threw for any ticket with a second assignee, taking the whole list down
  /// with it.
  Widget _avatars(List<String> ids, int more) {
    final step = 24.w - 7.w; // each avatar sits 7px into the one before it
    return Row(
      children: [
        if (ids.isNotEmpty)
          SizedBox(
            width: step * (ids.length - 1) + 24.w,
            height: 24.w,
            child: Stack(
              children: [
                for (int i = 0; i < ids.length; i++)
                  Positioned(
                    left: step * i,
                    child: Container(
                      width: 24.w,
                      height: 24.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MockUsers.of(ids[i]).color,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 2),
                      ),
                      child: Text(MockUsers.of(ids[i]).initials,
                          style: AppText.custom(
                              size: 9, weight: FontWeight.w700, color: AppColors.white)),
                    ),
                  ),
              ],
            ),
          ),
        if (more > 0) ...[
          SizedBox(width: 4.w),
          Text('+$more', style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textMuted2)),
        ],
      ],
    );
  }
}

/// The small tinted SLA pill (icon + text) used on ticket cards.
class TicketSlaPill extends StatelessWidget {
  const TicketSlaPill({super.key, required this.chip});
  final SlaChip chip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 4.h),
      decoration: BoxDecoration(color: chip.bg, borderRadius: BorderRadius.circular(7.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chip.icon, size: 11.sp, color: chip.tone),
          SizedBox(width: 5.w),
          Text(chip.text, style: AppText.custom(size: 11, weight: FontWeight.w700, color: chip.tone)),
        ],
      ),
    );
  }
}
