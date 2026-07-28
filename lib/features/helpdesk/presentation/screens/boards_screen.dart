import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/tickets_providers.dart';
import '../../domain/entities/ticket.dart';
import '../components/board_row.dart';
import '../util/ticket_sla.dart';

/// Support Overview — a read-only SLA monitoring board: a live-ish header with a
/// refresh chip, a 4-up stat strip, and four collapsible SLA-watch sections.
class BoardsScreen extends ConsumerStatefulWidget {
  const BoardsScreen({super.key});

  @override
  ConsumerState<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends ConsumerState<BoardsScreen> {
  String _updatedLabel = 'Updated 30s ago';

  static const _sections = [
    ('breached', 'Breached'),
    ('lt1h', 'Due < 1h'),
    ('today', 'Due today'),
    ('ontrack', 'On track'),
  ];

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider).valueOrNull ?? const [];
    final expanded = ref.watch(boardExpandedProvider);

    final buckets = <String, List<Ticket>>{'breached': [], 'lt1h': [], 'today': [], 'ontrack': []};
    for (final t in tickets) {
      final st = boardState(t);
      if (st != null) buckets[st]!.add(t);
    }
    // Sort each bucket by due proximity (soonest first).
    for (final k in buckets.keys) {
      buckets[k]!.sort((a, b) => _due(a).compareTo(_due(b)));
    }

    final open = buckets.values.fold<int>(0, (a, b) => a + b.length);
    final closedToday = tickets.where((t) => (t.resolved ?? '').startsWith('09 Jul')).length;

    return Column(
      children: [
        _header(open, buckets, closedToday),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(2.w, 2.h, 2.w, 10.h),
                child: Text('SLA WATCH',
                    style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.8)),
              ),
              for (final (key, name) in _sections)
                _sectionCard(key, name, buckets[key]!, expanded[key] ?? false),
            ],
          ),
        ),
      ],
    );
  }

  int _due(Ticket t) {
    final iso = (t.responded == null && t.respByISO != null) ? t.respByISO : t.resolveByISO;
    return iso == null ? 1 << 62 : DateTime.parse(iso).millisecondsSinceEpoch;
  }

  Widget _header(int open, Map<String, List<Ticket>> buckets, int closedToday) {
    final stats = <(String, String, Color)>[
      ('Open', '$open', AppColors.textPrimary),
      ('Breached', '${buckets['breached']!.length}', AppColors.error),
      ('Due today', '${buckets['lt1h']!.length + buckets['today']!.length}', AppColors.textPrimary),
      ('Closed today', '$closedToday', AppColors.textPrimary),
    ];
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.fromLTRB(18.w, 56.h, 18.w, 12.h),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderCardSoft))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Helpdesk', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 1.h),
                    Text('Support Overview', style: AppText.screenTitle()),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => _updatedLabel = 'Updated just now');
                  ref.read(toastProvider.notifier).show('Board refreshed just now');
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: AppColors.borderChip),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.arrowsClockwise, size: 14.sp, color: AppColors.textMuted),
                      SizedBox(width: 6.w),
                      Text(_updatedLabel, style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Container(
            padding: EdgeInsets.symmetric(vertical: 11.h),
            decoration: BoxDecoration(color: AppColors.bgScreen, borderRadius: BorderRadius.circular(13.r)),
            child: Row(
              children: [
                for (int i = 0; i < stats.length; i++)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.borderChip)),
                      ),
                      child: Column(
                        children: [
                          Text(stats[i].$2, style: AppText.custom(size: 19, weight: FontWeight.w800, color: stats[i].$3, letterSpacing: -0.4)),
                          SizedBox(height: 1.h),
                          Text(stats[i].$1, style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String key, String name, List<Ticket> rows, bool expanded) {
    final isBreached = key == 'breached';
    final shown = rows.take(8).toList();
    final moreCount = rows.length - shown.length;
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.borderCardSoft),
        boxShadow: [
          BoxShadow(color: const Color(0xFF101828).withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: const Color(0xFF101828).withOpacity(0.05), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final next = Map<String, bool>.from(ref.read(boardExpandedProvider));
              next[key] = !expanded;
              ref.read(boardExpandedProvider.notifier).state = next;
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              child: Row(
                children: [
                  Text(name, style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(width: 9.w),
                  Container(
                    constraints: BoxConstraints(minWidth: 24.w),
                    height: 22.h,
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(horizontal: 7.w),
                    decoration: BoxDecoration(
                      color: isBreached ? AppColors.tintRed : AppColors.bgChipGrey,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text('${rows.length}',
                        style: AppText.custom(size: 12, weight: FontWeight.w800, color: isBreached ? AppColors.error : AppColors.textLabelAlt)),
                  ),
                  if (isBreached) ...[
                    SizedBox(width: 9.w),
                    Text('▲1 today', style: AppText.custom(size: 11, weight: FontWeight.w800, color: AppColors.error)),
                  ],
                  const Spacer(),
                  Icon(expanded ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 13.sp, color: AppColors.textPlaceholder),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
              child: Column(
                children: [
                  if (rows.isEmpty)
                    Container(
                      padding: EdgeInsets.only(top: 18.h, bottom: 14.h),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIconsRegular.checkCircle, size: 15.sp, color: AppColors.tealLight),
                          SizedBox(width: 7.w),
                          Text('Nothing breaching soon',
                              style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.tealLight)),
                        ],
                      ),
                    )
                  else ...[
                    for (final t in shown)
                      BoardRow(
                        ticket: t,
                        onTap: () => context.push('${Routes.ticketDetail}?id=${t.id}&from=board'),
                      ),
                    if (moreCount > 0)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => context.go(Routes.tickets),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('+$moreCount more', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.blueBright)),
                              SizedBox(width: 6.w),
                              Icon(PhosphorIconsBold.arrowRight, size: 12.sp, color: AppColors.blueBright),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
