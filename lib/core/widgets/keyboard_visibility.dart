import 'package:flutter/widgets.dart';

/// Publishes whether the software keyboard is currently on screen.
///
/// A routed screen cannot ask MediaQuery this. The shell's `Scaffold` resizes
/// for the keyboard (`resizeToAvoidBottomInset`), and a Scaffold that resizes
/// **strips** the bottom `viewInsets` from the MediaQuery it hands its body —
/// so every screen below it reads `viewInsets.bottom == 0` whether the keyboard
/// is up or not. [ClozrShell] measures the inset above the Scaffold, where it
/// is still truthful, and publishes the answer here.
///
/// Screens use it to get out of the keyboard's way: a sticky footer that would
/// otherwise sit pinned between the field being typed into and the keyboard, a
/// bottom nav that would float on top of it.
class KeyboardVisibility extends InheritedWidget {
  const KeyboardVisibility({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  /// True while the keyboard is on screen; false outside the shell.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KeyboardVisibility>()?.visible ??
      false;

  @override
  bool updateShouldNotify(KeyboardVisibility oldWidget) =>
      oldWidget.visible != visible;
}
