import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../features/onboarding/presentation/tour_layer.dart';
import '../features/shell/presentation/notification_banner.dart';
import '../features/shell/presentation/offline_banner.dart';
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
          // 24-hour clocks app-wide (C17): time pickers follow this flag.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: MediaQuery.withNoTextScaling(
              // The toast sits here, above the navigator, so it is visible over
              // routed screens **and** over the bottom sheets that open on the
              // root navigator. Inside the shell it was hidden behind any open
              // sheet, which is where most write errors are raised.
              child: Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  const OfflineBanner(),
                  // Product tours — below the toast so a toast stays readable
                  // over a spotlight.
                  const TourLayer(),
                  const ToastOverlay(),
                  // Incoming-notification popup; same "above everything"
                  // reasoning as the toast.
                  const NotificationBanner(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
