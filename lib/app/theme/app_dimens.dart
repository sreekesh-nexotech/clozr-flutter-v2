import 'dart:ui';

/// Layout primitives from the design system (`_ds/tokens/spacing.css`) and the
/// prototype. The design canvas is 390×844 (see [designSize]).
///
/// All values are raw design-pixels. Multiply by ScreenUtil extensions at the
/// call site (`.w`, `.h`, `.r`, `.sp`) so the UI scales across devices.
class AppDimens {
  AppDimens._();

  /// Figma / prototype base canvas.
  static const double designWidth = 390;
  static const double designHeight = 844;

  // Screen padding
  static const double screenPadH = 18; // horizontal gutter on every screen
  static const double statusBarTop = 56; // top padding that clears the status bar
  static const double listBottomPad = 120; // clears the floating bottom nav

  // Radii
  static const double rCard = 16;
  static const double rCardLg = 18; // lead cards
  static const double rInput = 8;
  static const double rInputLg = 13; // search field
  static const double rPill = 999;
  static const double rSheet = 24;
  static const double rChip = 10;

  // Bottom nav
  static const double navOuterHeight = 88;
  static const double navInnerHeight = 64;

  // Common icon button
  static const double iconBtn = 40;
}

/// The ScreenUtil design size, referenced from `main.dart`.
const Size designSize = Size(AppDimens.designWidth, AppDimens.designHeight);
