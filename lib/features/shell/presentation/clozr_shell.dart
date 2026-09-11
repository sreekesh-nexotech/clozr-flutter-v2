import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/network/app_error.dart';
import '../../../core/network/connectivity_provider.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/widgets/keyboard_visibility.dart';
import '../../auth/application/providers/auth_providers.dart';
import '../application/providers/contextual_add_provider.dart';
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
    // Started here, not just by [AppDrawer], so the role is known — and the
    // router's landing-screen redirect can act on it — the moment any
    // authenticated screen builds, not only once the user happens to open
    // the drawer.
    ref.watch(moduleAccessProvider);

    // Reset the bottom nav's `+` action on every real navigation, so a screen
    // that registers nothing (a section's Home, Helpdesk Boards) falls
    // through to the nav's own default instead of keeping whatever the last
    // registering screen set.
    clearAddActionOnRouteChange(ref, location.split('?').first);

    // Every rejected write, and every permission refusal, gets said out loud
    // once — here, rather than at each call site.
    //
    // Most reach a screen that reports them itself, but several deliberately do
    // not: the best-effort fetches swallow theirs so an unreadable layout never
    // blanks the page, and the notes composer keeps its optimistic entry rather
    // than losing what was typed. Both are the right local choice and both used
    // to end with the user seeing nothing at all. Listening at the shell covers
    // them without changing what any screen does on its fallback path.
    ref.listen(apiFailureProvider, (_, failure) {
      if (failure == null) return;
      // The persistent [OfflineBanner] already says this, off the device's
      // own connectivity state rather than a failed request — a toast on top
      // would just repeat it a beat later for every write attempted while
      // offline, one after another.
      if (failure.type == AppErrorType.network) return;
      // A screen that already reported this has said the same sentence;
      // re-showing it would only restart the timer on a toast being read.
      if (ref.read(toastProvider)?.text == failure.message) return;
      ref.read(toastProvider.notifier).showError(failure.message);
    });

    // Reconnecting should replace stale data, not just recolor the banner.
    // Every repository-backed provider reaches the network through
    // `apiServiceProvider` (`ref.watch`, not `ref.read`), so invalidating it
    // here cascades into a live refetch of all of them — the same mechanic
    // `SessionController._resetApiScopedProviders` already uses on logout,
    // just without touching the session. Only fires on a genuine
    // offline→online transition, never on the steady "still online" ticks the
    // connectivity stream can also emit.
    ref.listen(isOnlineProvider, (previous, next) {
      final wasOnline = previous?.valueOrNull;
      final isOnline = next.valueOrNull;
      if (isOnline == true && wasOnline == false) {
        ref.invalidate(apiServiceProvider);
      }
    });

    // Read HERE, above the Scaffold: a Scaffold that resizes for the keyboard
    // removes the bottom inset from the MediaQuery it gives its body, so this
    // is the last point in the tree where the question can still be answered.
    // Published to the routed screens via [KeyboardVisibility] below.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

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
      child: KeyboardVisibility(
        visible: keyboardOpen,
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
          //
          // While the keyboard is up the screen also becomes tap-to-dismiss:
          // otherwise there is no way out of a focused field except the search
          // field's own × chip, and the keyboard sits over half the results.
          // Translucent, so a tap that lands on something interactive is still
          // claimed by that child — only dead space reaches this recogniser.
          Positioned.fill(
            child: SafeArea(
              top: false,
              bottom: true,
              child: keyboardOpen
                  ? GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                      child: child,
                    )
                  : child,
            ),
          ),

          // Bottom nav (conditional) — lifts itself above the gesture inset.
          // Hidden while the keyboard is up: the Scaffold shrinks the Stack by
          // the inset, so a bottom-anchored nav is not covered by the keyboard,
          // it is glued to the top of it — floating over the list on every
          // search-open screen.
          if (meta.showNav && !keyboardOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClozrBottomNav(location: location),
            ),

          // Drawer.
          if (drawerOpen) Positioned.fill(child: AppDrawer(location: location)),

          // The toast is NOT here: it lives above the navigator (see
          // [ToastOverlay] in app.dart), because bottom sheets open on the
          // root navigator and would otherwise cover it.
            ],
          ),
        ),
      ),
    );
  }
}
