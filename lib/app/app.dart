import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../features/shell/presentation/toast_overlay.dart';
import 'config/constants.dart';
import 'router/app_router.dart';
import 'theme/app_dimens.dart';
import 'theme/app_theme.dart';

/// Root widget — sets up ScreenUtil against the 390×844 design canvas and the
/// GoRouter. Kept thin per the coding standards.
class ClozrApp extends StatelessWidget {
  const ClozrApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    return ScreenUtilInit(
      designSize: designSize,
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: AppConstants.brandName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          routerConfig: appRouter,
          // Lock text scaling to 1.0 so the dense layout matches the design.
          builder: (context, child) => MediaQuery.withNoTextScaling(
            // The toast sits here, above the navigator, so it is visible over
            // routed screens **and** over the bottom sheets that open on the
            // root navigator. Inside the shell it was hidden behind any open
            // sheet, which is where most write errors are raised.
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                const ToastOverlay(),
              ],
            ),
          ),
        );
      },
    );
  }
}
