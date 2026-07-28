import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'app_colors.dart';

/// Typography for Clozr — Manrope variable font (self-hosted).
///
/// The prototype uses a compact, data-dense scale. Helpers return styles with
/// ScreenUtil `.sp` sizing so text scales with the viewport. Letter-spacing
/// mirrors the design's tight `-0.5px` headings.
class AppText {
  AppText._();

  static const String fontFamily = 'Manrope';

  /// Base builder — every style funnels through here so the family and default
  /// colour are consistent.
  static TextStyle _s({
    required double size,
    required FontWeight weight,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size.sp,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    );
  }

  // ── Headings ──
  static TextStyle screenTitle({Color color = AppColors.textPrimary}) =>
      _s(size: 24, weight: FontWeight.w800, color: color, letterSpacing: -0.5);

  static TextStyle h1({Color color = AppColors.textPrimary}) =>
      _s(size: 22, weight: FontWeight.w800, color: color, letterSpacing: -0.5);

  static TextStyle logo() =>
      _s(size: 19, weight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.5);

  static TextStyle cardTitle({Color color = AppColors.textPrimary}) =>
      _s(size: 15, weight: FontWeight.w700, color: color);

  static TextStyle sectionTitle({Color color = AppColors.textPrimary}) =>
      _s(size: 16, weight: FontWeight.w700, color: color);

  // ── Body ──
  static TextStyle bodyStrong({Color color = AppColors.textPrimary}) =>
      _s(size: 14, weight: FontWeight.w600, color: color);

  static TextStyle body({Color color = AppColors.textBody}) =>
      _s(size: 14, weight: FontWeight.w500, color: color);

  static TextStyle bodyMuted({Color color = AppColors.textMuted}) =>
      _s(size: 14, weight: FontWeight.w500, color: color);

  // ── Captions / meta ──
  static TextStyle caption({Color color = AppColors.textMuted}) =>
      _s(size: 12, weight: FontWeight.w500, color: color);

  static TextStyle captionStrong({Color color = AppColors.textMuted}) =>
      _s(size: 12, weight: FontWeight.w600, color: color);

  static TextStyle micro({Color color = AppColors.textPlaceholder}) =>
      _s(size: 11, weight: FontWeight.w500, color: color);

  // ── Numeric / KPI ──
  static TextStyle kpiNumber({Color color = AppColors.textPrimary}) =>
      _s(size: 25, weight: FontWeight.w800, color: color, letterSpacing: -0.6);

  static TextStyle statNumber({Color color = AppColors.textPrimary}) =>
      _s(size: 20, weight: FontWeight.w800, color: color, letterSpacing: -0.3);

  // ── Pills / chips ──
  static TextStyle pill({required Color color}) =>
      _s(size: 12, weight: FontWeight.w700, color: color);

  static TextStyle pillSmall({required Color color}) =>
      _s(size: 11, weight: FontWeight.w700, color: color);

  // ── Nav ──
  static TextStyle navLabel({required Color color}) =>
      _s(size: 11, weight: FontWeight.w600, color: color, letterSpacing: 0.1);

  /// Escape hatch for one-off sizes present in the prototype.
  static TextStyle custom({
    required double size,
    required FontWeight weight,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      _s(
        size: size,
        weight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );
}
