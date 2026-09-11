import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A page-supplied "add" action for the bottom-nav `+` button (#14).
///
/// Each list screen registers what its `+` should do — usually opening that
/// entity's add sheet/form. The bottom nav reads this and invokes it, so the
/// single global `+` is always contextual to the current screen. When a screen
/// registers nothing, the nav falls back to a route-based default.
class AddAction {
  const AddAction({required this.label, required this.run});

  /// e.g. "Add lead", "New project" — used for a11y / tooltip.
  final String label;

  /// Opens the relevant add form or sheet.
  final void Function(BuildContext context) run;
}

/// Holds the current screen's add action, or null when none is registered.
final contextualAddProvider = StateProvider<AddAction?>((ref) => null);

/// The route path [ClozrShell] last cleared [contextualAddProvider] for.
/// Internal bookkeeping for [clearAddActionOnRouteChange] — not read
/// anywhere else.
final _lastAddRoutePathProvider = StateProvider<String?>((ref) => null);

/// Mixin helper for screens: call [registerAdd] from build to publish the
/// screen's add action, and it self-clears is unnecessary because the next
/// screen overwrites it. Kept as a free function for use in both stateless and
/// stateful consumers.
void registerAdd(WidgetRef ref, AddAction? action) {
  // Defer so we don't mutate provider state during a build.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!ref.context.mounted) return;
    final current = ref.read(contextualAddProvider);
    if (current != action) {
      ref.read(contextualAddProvider.notifier).state = action;
    }
  });
}

/// Clears the `+` action on a real route change, called once from
/// [ClozrShell]'s build with the current path.
///
/// [registerAdd] only ever sets the action — nothing ever cleared it, so a
/// screen that registers nothing (every dashboard/home screen, Helpdesk
/// Boards) kept showing whatever the *last* registering screen set, however
/// unrelated. Clearing it here first and letting a registering screen's own
/// [registerAdd] call — scheduled after this one, since the shell builds
/// before the routed child — put its action back is what makes a
/// non-registering screen actually fall through to the nav's route-based
/// default instead of showing stale state.
void clearAddActionOnRouteChange(WidgetRef ref, String path) {
  if (ref.read(_lastAddRoutePathProvider) == path) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Re-check inside the callback: a rapid rebuild before this one fires
    // would otherwise queue a second clear that wipes the very action the
    // first callback's screen just registered.
    if (ref.read(_lastAddRoutePathProvider) == path) return;
    ref.read(_lastAddRoutePathProvider.notifier).state = path;
    ref.read(contextualAddProvider.notifier).state = null;
  });
}
