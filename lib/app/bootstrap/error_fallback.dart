import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Branded replacement for Flutter's default grey/red error box, shown by
/// [ErrorWidget.builder] if a widget build throws. Deliberately dependency-free
/// (no ScreenUtil) so it renders even if the failure is in the theme/layout.
class AppErrorFallback extends StatelessWidget {
  const AppErrorFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.bgScreen,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Something went wrong on this screen.\nPlease go back and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
