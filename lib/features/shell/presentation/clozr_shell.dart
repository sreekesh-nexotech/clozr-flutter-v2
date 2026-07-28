import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../application/providers/shell_providers.dart';
import 'app_drawer.dart';
import 'clozr_bottom_nav.dart';
import 'device_status_bar.dart';

/// The persistent device frame that wraps every routed screen: the routed
/// child, the simulated status bar, the conditional bottom nav, the drawer,
/// the toast and the home indicator — all in one Stack, matching the
/// prototype's fixed-overlay layout.
class ClozrShell extends ConsumerWidget {
  const ClozrShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final meta = Routes.metaFor(location);
    final drawerOpen = ref.watch(drawerOpenProvider);
    final toast = ref.watch(toastProvider);

    return Scaffold(
      backgroundColor: AppColors.bgScreen,
      body: Stack(
        children: [
          // Routed screen fills the frame.
          Positioned.fill(child: child),

          // Bottom nav (conditional).
          if (meta.showNav)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClozrBottomNav(location: location),
            ),

          // Status bar overlay (always on top).
          Positioned(top: 0, left: 0, right: 0, child: const DeviceStatusBar()),

          // Drawer.
          if (drawerOpen) Positioned.fill(child: AppDrawer(location: location)),

          // Toast.
          if (toast != null) _Toast(message: toast),

          // Home indicator.
          Positioned(
            bottom: 8.h,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 134.w,
                  height: 5.h,
                  decoration: BoxDecoration(
                    color: AppColors.black.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(3.r),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 106.h,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 17.w, vertical: 12.h),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withOpacity(0.34),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsFill.checkCircle, size: 18.sp, color: AppColors.toastCheck),
                SizedBox(width: 9.w),
                Text(message,
                    style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
