import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../network/app_error.dart';

/// Centered error-state block — the visual twin of [EmptyState] but in the
/// error palette, with a Retry CTA. Shown when a data provider fails (an
/// [AppError]) so a genuine failure is never mistaken for "no data".
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.body,
    this.icon = PhosphorIconsFill.warningCircle,
    this.title = 'Something went wrong',
    this.iconColor = AppColors.error,
    this.iconBg = AppColors.tintRed,
    this.ctaLabel = 'Retry',
    this.ctaIcon = PhosphorIconsBold.arrowClockwise,
    this.onRetry,
  });

  final String body;
  final IconData icon;
  final String title;
  final Color iconColor;
  final Color iconBg;
  final String? ctaLabel;
  final IconData? ctaIcon;
  final VoidCallback? onRetry;

  /// Maps an [AppError] onto a friendly icon/title, using its already
  /// user-safe [AppError.message] as the body.
  factory ErrorState.forError(AppError error, {VoidCallback? onRetry}) {
    final (icon, title) = switch (error.type) {
      AppErrorType.network => (PhosphorIconsFill.wifiSlash, "You're offline"),
      AppErrorType.timeout => (PhosphorIconsFill.clockCountdown, 'Taking too long'),
      AppErrorType.forbidden => (PhosphorIconsFill.lock, 'No access'),
      AppErrorType.notFound => (PhosphorIconsFill.magnifyingGlass, 'Not found'),
      AppErrorType.server => (PhosphorIconsFill.cloudSlash, 'Server error'),
      _ => (PhosphorIconsFill.warningCircle, 'Something went wrong'),
    };
    return ErrorState(
      body: error.message,
      icon: icon,
      title: title,
      onRetry: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 56.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66.r,
            height: 66.r,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(19.r)),
            child: Icon(icon, size: 30.sp, color: iconColor),
          ),
          SizedBox(height: 16.h),
          Text(title, style: AppText.sectionTitle(), textAlign: TextAlign.center),
          SizedBox(height: 6.h),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 240.w),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.textMuted).copyWith(height: 1.5),
            ),
          ),
          if (ctaLabel != null && onRetry != null) ...[
            SizedBox(height: 18.h),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ctaIcon != null) ...[
                      Icon(ctaIcon, size: 15.sp, color: AppColors.white),
                      SizedBox(width: 8.w),
                    ],
                    Text(ctaLabel!, style: AppText.bodyStrong(color: AppColors.white)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
