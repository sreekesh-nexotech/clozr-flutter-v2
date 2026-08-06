import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    // Handle the OS/hardware Back button (#11). Without this, screens reached
    // via context.go (bottom nav / drawer) flatten the stack, so Back exits the
    // app straight to the phone home screen. Instead: close an open drawer, then
    // pop the router if it can, then fall back to the Dashboard (the app's
    // landing screen), and only exit from the Dashboard.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (ref.read(drawerOpenProvider)) {
          ref.read(drawerOpenProvider.notifier).state = false;
          return;
        }
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
          return;
        }
        if (location.split('?').first != Routes.dashboard) {
          context.go(Routes.dashboard);
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgScreen,
        body: Stack(
          children: [
          // Routed screen. Headers stay edge-to-edge under the real status bar
          // (their own top padding clears it); the bottom SafeArea keeps every
          // screen's bottom-anchored content (sticky CTAs, list ends) above the
          // OS gesture/navigation bar on all device sizes. The simulated iOS
          // status bar and home-indicator from the design canvas are gone — the
          // real OS draws those.
          Positioned.fill(
            child: SafeArea(top: false, bottom: true, child: child),
          ),

          // Bottom nav (conditional) — lifts itself above the gesture inset.
          if (meta.showNav)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClozrBottomNav(location: location),
            ),

          // Drawer.
          if (drawerOpen) Positioned.fill(child: AppDrawer(location: location)),

          // Toast.
          if (toast != null) _Toast(message: toast),
          ],
        ),
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
      bottom: 106.h + MediaQuery.viewPaddingOf(context).bottom,
      left: 0,
      right: 0,
      child: IgnorePointer(
        // The toast carries whatever the backend said, and a validation error
        // is a sentence, not a word ("A task must have at least one note
        // before it can be completed."). Without a width bound the row simply
        // grew past the screen and overflowed; it has to wrap instead.
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
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
                  // Flexible, not Expanded: a short message still gets a
                  // snug pill rather than one stretched to the full width.
                  Flexible(
                    child: Text(
                      message,
                      // Bounded so a pathological message cannot cover the
                      // screen, but generous enough that no realistic
                      // validation error is cut off.
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(
                              size: 13, weight: FontWeight.w600, color: AppColors.white)
                          .copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
