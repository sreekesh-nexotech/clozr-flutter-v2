import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/notifications_providers.dart';
import '../../domain/entities/app_notification.dart';
import '../components/notification_row.dart';

/// Full-screen Notifications page: grouped (Today/Yesterday/Earlier), All|Unread
/// segmented filter, Mark-all, deep-linking rows, pagination, and
/// loading/empty states.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static const _dayLabels = {'today': 'TODAY', 'yesterday': 'YESTERDAY', 'earlier': 'EARLIER'};
  static const _dayOrder = ['today', 'yesterday', 'earlier'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final ctrl = ref.read(notificationsProvider.notifier);

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          _header(context, ref, state, ctrl),
          Expanded(
            child: state.loading
                ? _skeletons()
                : state.visible.isEmpty
                    ? _empty(state.filter)
                    : ListView(
                        padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 30.h),
                        children: [
                          ..._buildGroups(context, ref, state, ctrl),
                          if (state.hasMore) _loadMore(state, ctrl),
                          if (!state.hasMore && state.visible.isNotEmpty) _allCaughtUp(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref, NotificationsState state, NotificationsController ctrl) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 12.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _squareBtn(PhosphorIconsBold.caretLeft, () => context.pop()),
              SizedBox(width: 12.w),
              Text('Notifications',
                  style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
              SizedBox(width: 8.w),
              if (state.unreadCount > 0)
                Container(
                  constraints: BoxConstraints(minWidth: 22.w),
                  height: 22.w,
                  padding: EdgeInsets.symmetric(horizontal: 7.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                  child: Text('${state.unreadCount}',
                      style: AppText.custom(size: 11.5, weight: FontWeight.w800, color: AppColors.white)),
                ),
              const Spacer(),
              _squareBtn(PhosphorIconsRegular.arrowsClockwise, ctrl.refresh),
            ],
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                child: Text('${state.unreadCount} unread',
                    style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textMuted)),
              ),
              _segmented(state, ctrl),
              SizedBox(width: 10.w),
              GestureDetector(
                onTap: () {
                  ctrl.markAllRead();
                  ref.read(toastProvider.notifier).show('All marked as read');
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsBold.checks, size: 14.sp, color: AppColors.blueBright),
                    SizedBox(width: 5.w),
                    Text('Mark all',
                        style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.blueBright)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segmented(NotificationsState state, NotificationsController ctrl) {
    Widget seg(String label, NotifFilter f) {
      final on = state.filter == f;
      return GestureDetector(
        onTap: () => ctrl.setFilter(f),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
          decoration: BoxDecoration(
            color: on ? AppColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7.r),
            boxShadow: on
                ? [BoxShadow(color: const Color(0xFF101828).withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Text(label,
              style: AppText.custom(size: 12, weight: FontWeight.w700, color: on ? AppColors.navy : AppColors.textMuted)),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(2.r),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(9.r)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('All', NotifFilter.all), seg('Unread', NotifFilter.unread)]),
    );
  }

  Widget _squareBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38.w,
        height: 38.w,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: const Color(0xFFE6E7EA)),
        ),
        child: Icon(icon, size: 16.sp, color: AppColors.textLabelAlt),
      ),
    );
  }

  List<Widget> _buildGroups(BuildContext context, WidgetRef ref, NotificationsState state, NotificationsController ctrl) {
    final widgets = <Widget>[];
    final visible = state.visible;
    for (final day in _dayOrder) {
      final rows = visible.where((n) => n.day == day).toList();
      if (rows.isEmpty) continue;
      widgets.add(_groupHeader(_dayLabels[day]!, state.dayCount(day)));
      for (final n in rows) {
        widgets.add(NotificationRow(
          notif: n,
          onOpen: () {
            ctrl.markRead(n.id);
            _openTarget(context, n);
          },
          onMenu: () => _openMenu(context, ref, ctrl, n),
        ));
      }
    }
    return widgets;
  }

  Widget _groupHeader(String label, int count) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2.w, 6.h, 2.w, 10.h),
      child: Row(
        children: [
          Text(label,
              style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.7)),
          SizedBox(width: 8.w),
          Text('$count',
              style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: const Color(0xFFC2C6CD))),
          SizedBox(width: 8.w),
          Expanded(child: Container(height: 1, color: const Color(0xFFE9EBEF))),
        ],
      ),
    );
  }

  Widget _loadMore(NotificationsState state, NotificationsController ctrl) {
    return GestureDetector(
      onTap: ctrl.loadMore,
      child: Container(
        height: 46.h,
        margin: EdgeInsets.only(top: 6.h),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: const Color(0xFFE6E7EA)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIconsBold.arrowDown, size: 13.sp, color: AppColors.blueBright),
            SizedBox(width: 7.w),
            Text('Load ${state.remaining} older',
                style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.blueBright)),
          ],
        ),
      ),
    );
  }

  Widget _allCaughtUp() => Padding(
        padding: EdgeInsets.only(top: 16.h, bottom: 4.h),
        child: Center(
          child: Text("You're all caught up",
              style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
        ),
      );

  Widget _skeletons() {
    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 30.h),
      children: [
        for (int i = 0; i < 5; i++)
          Container(
            margin: EdgeInsets.only(bottom: 8.h),
            padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: AppColors.borderCardSoft),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 38.w, height: 38.w, decoration: BoxDecoration(color: AppColors.borderCardSoft, borderRadius: BorderRadius.circular(11.r))),
                SizedBox(width: 11.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 12.h, width: 160.w, decoration: BoxDecoration(color: AppColors.borderCardSoft, borderRadius: BorderRadius.circular(6.r))),
                      SizedBox(height: 9.h),
                      Container(height: 10.h, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(6.r))),
                      SizedBox(height: 7.h),
                      Container(height: 10.h, width: 120.w, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(6.r))),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _empty(NotifFilter filter) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 26.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66.r,
              height: 66.r,
              decoration: BoxDecoration(color: AppColors.borderCardSoft, borderRadius: BorderRadius.circular(19.r)),
              child: Icon(PhosphorIconsRegular.bellSlash, size: 30.sp, color: AppColors.navy),
            ),
            SizedBox(height: 16.h),
            Text(filter == NotifFilter.unread ? 'No unread notifications' : 'No notifications',
                style: AppText.sectionTitle()),
            SizedBox(height: 6.h),
            Text(filter == NotifFilter.unread ? "You've read everything. Nice work." : 'New updates will show up here.',
                textAlign: TextAlign.center, style: AppText.body(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  void _openMenu(BuildContext context, WidgetRef ref, NotificationsController ctrl, AppNotification n) {
    showClozrSheet(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: 'Notification'),
            if (n.hasTarget)
              _menuItem(ctx, PhosphorIconsRegular.arrowSquareOut, 'Open record', () {
                Navigator.pop(ctx);
                ctrl.markRead(n.id);
                _openTarget(context, n);
              }),
            _menuItem(ctx, n.unread ? PhosphorIconsRegular.envelopeOpen : PhosphorIconsRegular.envelope,
                n.unread ? 'Mark as read' : 'Mark as unread', () {
              Navigator.pop(ctx);
              ctrl.toggleRead(n.id);
            }),
            _menuItem(ctx, PhosphorIconsRegular.trash, 'Delete', () {
              Navigator.pop(ctx);
              ctrl.delete(n.id);
              ref.read(toastProvider.notifier).show('Notification deleted');
            }, danger: true),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext ctx, IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
    final color = danger ? AppColors.error : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 15.h),
        child: Row(
          children: [
            Icon(icon, size: 19.sp, color: color),
            SizedBox(width: 14.w),
            Text(label, style: AppText.bodyStrong(color: color)),
          ],
        ),
      ),
    );
  }

  void _openTarget(BuildContext context, AppNotification n) {
    String? route;
    switch (n.targetKind) {
      case 'lead':
        route = '${Routes.leadDetail}?id=${n.targetId}';
        break;
      case 'payment':
        route = '${Routes.paymentDetail}?id=${n.targetId}';
        break;
      case 'followup':
        route = '${Routes.followupDetail}?id=${n.targetId}';
        break;
      case 'opstask':
        route = '${Routes.opsTaskDetail}?id=${n.targetId}';
        break;
      case 'ticket':
        route = '${Routes.ticketDetail}?id=${n.targetId}';
        break;
      case 'quote':
        route = '${Routes.quoteDetail}?id=${n.targetId}';
        break;
      case 'project':
        route = '${Routes.projectDetail}?id=${n.targetId}';
        break;
      case 'list':
        route = _listRoute(n.targetId);
        break;
    }
    if (route != null) context.push(route);
  }

  String _listRoute(String? id) {
    switch (id) {
      case 'payments':
        return Routes.payments;
      case 'lmsMy':
        return Routes.lmsMy;
      case 'rewards':
        return Routes.rewards;
      case 'billing':
        return Routes.billing;
      default:
        return Routes.home;
    }
  }
}
