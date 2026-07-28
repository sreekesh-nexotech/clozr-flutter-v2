import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';

/// Dashboard-scoped colour tokens. Most values re-export [AppColors]; the few
/// hues the shared palette does not carry (the aging teal, the funnel gradient
/// top, the segmented-control mid-grey) live here so widgets never hardcode hex.
class DashColors {
  DashColors._();

  // Extras not present in AppColors (from the prototype's inline styles).
  static const teal = Color(0xFF3AA0B8); // aging / outstanding teal band
  static const funnelTop = Color(0xFF4E7CC7); // lead-funnel gradient top stop
  static const textMid = Color(0xFF6C6C6C); // segmented inactive / pct labels
  static const chipStroke = Color(0xFFE6E7EA); // scope-chip inset border

  // Aliases onto the shared palette for readability.
  static const navy = AppColors.navy; // #00113B
  static const navyMid = AppColors.navyMid; // #152856
  static const green = AppColors.success; // #0E8F3D
  static const red = AppColors.error; // #E71111
  static const amber = AppColors.warning; // #EDA032
  static const amberDeep = AppColors.warningDeep; // #E2890D
  static const blue = AppColors.blueBright; // #074ADB
  static const purple = AppColors.pending; // #890DB6
  static const grey = AppColors.textPlaceholder; // #9AA0A6
  static const lowGrey = AppColors.textMuted; // #848383 (Low priority pill)

  static const tintGreen = AppColors.tintGreen; // #E7F6EC
  static const tintRed = AppColors.tintRed; // #FCEBEB
  static const tintBlue = AppColors.tintBlue; // #EEF6FF
  static const tintAmber = AppColors.tintAmber; // #FFF5EB
  static const track = AppColors.borderCardSoft; // #EEF0F3 chart track / hairline
  static const rowLine = AppColors.bgLight; // #F3F4F5 list-row hairline
  static const chipGrey = AppColors.bgChipGrey; // #F1F2F4
}
