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
