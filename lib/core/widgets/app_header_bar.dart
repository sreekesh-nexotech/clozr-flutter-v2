import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/config/constants.dart';
import '../../app/router/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../features/auth/application/providers/auth_providers.dart';
import '../../features/messages/application/providers/messages_providers.dart';
import '../../features/notifications/application/providers/notifications_providers.dart';
import '../../features/shell/application/providers/shell_providers.dart';

/// The brand header row shared by every list/home screen: tappable logo block
/// (opens the drawer), workspace name, messages icon (unread badge) and
/// notifications bell (unread dot).
///
/// The workspace label and both unread indicators come from live state — the
/// signed-in user's primary organization, the conversation list and the
/// notification list. Without a session (mock mode) the label falls back to the
/// seed workspace name so the prototype build is unchanged.
class AppHeaderBar extends ConsumerWidget {
  const AppHeaderBar({
    super.key,
    this.chatUnread,
    this.hasUnread,
  });

  /// Explicit overrides. Null at every call site today, which is what makes the
  /// badges read live state instead of a fixed value.
  final int? chatUnread;
  final bool? hasUnread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(sessionControllerProvider).user?.primaryOrg;
    final workspace = (org != null && org.name.isNotEmpty)
        ? org.name
        : AppConstants.workspaceName;

    final unreadChats = chatUnread ??
        ref
            .watch(conversationsProvider)
            .conversations
            .fold<int>(0, (sum, c) => sum + c.unread);
    final unreadNotifs =
        hasUnread ?? (ref.watch(notificationsProvider).unreadCount > 0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(drawerOpenProvider.notifier).state = true,
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
                child: Icon(PhosphorIconsFill.squaresFour, size: 20.sp, color: AppColors.white),
              ),
              SizedBox(width: 11.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      text: AppConstants.brandName,
                      style: AppText.logo(),
                      children: const [
                        TextSpan(text: '.', style: TextStyle(color: AppColors.blueBright)),
                      ],
                    ),
                  ),
                  SizedBox(height: 1.h),
                  Text(workspace, style: AppText.caption()),
                ],
              ),
            ],
          ),
        ),
        Row(
          children: [
            _iconButton(
              icon: PhosphorIconsRegular.chatsCircle,
              onTap: () => context.push(Routes.messages),
              badge: unreadChats > 0 ? '$unreadChats' : null,
            ),
            SizedBox(width: 10.w),
            _iconButton(
              icon: PhosphorIconsRegular.bell,
              onTap: () => context.push(Routes.notifications),
              dot: unreadNotifs,
            ),
          ],
        ),
      ],
    );
  }

  Widget _iconButton({
    required IconData icon,
    required VoidCallback onTap,
    String? badge,
    bool dot = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40.w,
        height: 40.w,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.borderChip),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 19.sp, color: AppColors.textSecondary),
            if (badge != null)
              Positioned(
                top: -5.h,
                right: -5.w,
                child: Container(
                  constraints: BoxConstraints(minWidth: 18.w),
                  height: 18.w,
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(9.r),
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                  child: Text(badge,
                      style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.white)),
                ),
              ),
            if (dot)
              Positioned(
                top: 9.h,
                right: 10.w,
                child: Container(
                  width: 7.w,
                  height: 7.w,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Title row with optional search + filter action buttons (used on list
/// screens). The filter button shows a count badge when [filterCount] > 0.
class ScreenTitleRow extends StatelessWidget {
  const ScreenTitleRow({
    super.key,
    required this.title,
    this.onSearch,
    this.onFilter,
    this.hasSearchQuery = false,
    this.filterCount = 0,
    this.trailing,
  });

  final String title;
  final VoidCallback? onSearch;
  final VoidCallback? onFilter;
  final bool hasSearchQuery;
  final int filterCount;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(title, style: AppText.screenTitle())),
        if (trailing != null) trailing!,
        if (onSearch != null)
          _action(
            icon: PhosphorIconsRegular.magnifyingGlass,
            onTap: onSearch!,
            dot: hasSearchQuery,
          ),
        if (onFilter != null)
          _action(
            icon: PhosphorIconsRegular.slidersHorizontal,
            onTap: onFilter!,
            badge: filterCount > 0 ? '$filterCount' : null,
          ),
      ],
    );
  }

  Widget _action({required IconData icon, required VoidCallback onTap, bool dot = false, String? badge}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38.w,
        height: 38.w,
        margin: EdgeInsets.only(left: 2.w),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 20.sp, color: AppColors.textSecondary),
            if (dot)
              Positioned(
                top: 7.h,
                right: 7.w,
                child: Container(
                  width: 7.w,
                  height: 7.w,
                  decoration: BoxDecoration(
                    color: AppColors.blueBright,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                ),
              ),
            if (badge != null)
              Positioned(
                top: 2.h,
                right: 2.w,
                child: Container(
                  constraints: BoxConstraints(minWidth: 16.w),
                  height: 16.w,
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.blueBright,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(badge,
                      style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
