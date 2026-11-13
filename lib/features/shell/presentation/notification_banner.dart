import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../notifications/application/notification_navigator.dart';
import '../../notifications/application/providers/notification_banner_provider.dart';
import '../../notifications/presentation/components/notification_icons.dart';

/// The in-app notification popup: a card that slides down from the top when
/// a notification arrives while the app is open.
///
/// * Tap → marks it read and opens the record (same destination as the inbox).
/// * Swipe left or right, or the × → closes it.
/// * Left alone → closes itself after
///   [AppConstants.notificationBannerDuration] (15 s).
///
/// Mounted in `MaterialApp.builder`, above the navigator, for the same reason
/// the toast is: it has to show over whatever screen or sheet is open.
class NotificationBanner extends ConsumerWidget {
  const NotificationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the poll fallback alive for as long as the app is running.
    ref.watch(newNotificationWatcherProvider);
    final n = ref.watch(incomingNotificationProvider);
    final top = MediaQuery.viewPaddingOf(context).top + 8.h;

    return Positioned(
      top: top,
      left: 12.w,
      right: 12.w,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
                  .animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: n == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : Dismissible(
                key: ValueKey('banner-${n.id}'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) =>
                    ref.read(incomingNotificationProvider.notifier).dismiss(),
                child: _Card(
                  n: n,
                  onClose: () =>
                      ref.read(incomingNotificationProvider.notifier).dismiss(),
                  onOpen: () {
                    ref.read(incomingNotificationProvider.notifier).dismiss();
                    openNotification(ProviderScope.containerOf(context),
                        GoRouter.maybeOf(context) ?? appRouter, n);
                  },
                ),
              ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.n, required this.onClose, required this.onOpen});

  final dynamic n;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final look = notificationLook(n);
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: true,
        label: 'Notification: ${n.title}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Container(
            padding: EdgeInsets.fromLTRB(12.w, 12.h, 6.w, 12.h),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: const Color(0xFFE6E7EA)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF101828).withOpacity(0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36.w,
                  height: 36.w,
                  decoration:
                      BoxDecoration(color: look.bg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Icon(look.icon, size: 18.sp, color: look.color),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(
                                size: 13.5,
                                weight: FontWeight.w700,
                                color: AppColors.textPrimary)
                            .copyWith(height: 1.3),
                      ),
                      if ((n.body as String).isNotEmpty) ...[
                        SizedBox(height: 2.h),
                        Text(
                          n.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(
                              size: 12,
                              weight: FontWeight.w500,
                              color: AppColors.textMuted),
                        ),
                      ],
                      SizedBox(height: 4.h),
                      Text(
                        '${n.categoryLabel} · Tap to open',
                        style: AppText.custom(
                            size: 11,
                            weight: FontWeight.w600,
                            color: AppColors.textPlaceholder),
                      ),
                    ],
                  ),
                ),
                // Close — kept its own tap target so a miss does not open the
                // record instead.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Padding(
                    padding: EdgeInsets.all(6.r),
                    child: Icon(PhosphorIconsBold.x,
                        size: 16.sp, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
