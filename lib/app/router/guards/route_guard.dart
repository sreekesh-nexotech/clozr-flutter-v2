import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Decides whether a navigation may proceed.
///
/// Returns `null` to allow it, or the path to redirect to instead. This is the
/// signature GoRouter's `redirect:` expects, so a guard drops straight into a
/// route definition.
typedef RouteGuard = String? Function(BuildContext context, GoRouterState state);

/// Composition helpers for [RouteGuard]s.
///
/// NOT WIRED YET: `app_router.dart` declares no `redirect:`, so navigation is
/// unchanged. Add guards here — an auth guard that bounces signed-out users to
/// login, a permission guard for admin-only screens — and attach them to the
/// routes that need them.
// TODO(clozr): add auth + permission guards when the session layer lands 2026-07-28
class RouteGuards {
  const RouteGuards._();

  /// Runs [guards] in order and returns the first redirect, or `null` when
  /// every guard allows the navigation.
  ///
  /// Order matters: put the cheapest and most fundamental check first, so an
  /// unauthenticated user is redirected before any permission lookup runs.
  static RouteGuard chain(List<RouteGuard> guards) {
    return (context, state) {
      for (final guard in guards) {
        final redirect = guard(context, state);
        if (redirect != null) return redirect;
      }
      return null;
    };
  }
}
