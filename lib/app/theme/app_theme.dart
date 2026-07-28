import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Assembled [ThemeData] for Clozr. The design is a single (light) theme; we
/// pin Manrope as the default family and map the brand palette onto Material's
/// [ColorScheme] so stock widgets inherit sane defaults.
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.navy,
      onPrimary: AppColors.white,
      secondary: AppColors.blueBright,
      onSecondary: AppColors.white,
      error: AppColors.error,
      onError: AppColors.white,
      surface: AppColors.white,
      onSurface: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Manrope',
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bgScreen,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.blueBright,
        selectionColor: Color(0x33074ADB),
        selectionHandleColor: AppColors.blueBright,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      // The prototype never uses the Material ripple; interactions are flat.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
