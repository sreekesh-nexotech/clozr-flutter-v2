import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'app_header_bar.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// Temporary screen shown for routes whose real UI is built in a later module
/// pass. Never shipped — every stub is replaced by its module implementation.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    this.body,
    this.showHeader = false,
  });

  final String title;

  /// Replaces the default "coming in this build" line. Used where the screen is
  /// not merely unbuilt but deliberately lives elsewhere.
  final String? body;

  /// Renders the app header, which carries the drawer button.
  ///
  /// Needed by any stub reached as a **landing** destination rather than pushed
  /// on top of something: the header is per-screen, so without it — and with
  /// the bottom nav switched off — the screen has no way out at all.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      color: AppColors.bgScreen,
      padding: EdgeInsets.only(top: 56.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66.r,
              height: 66.r,
              decoration: BoxDecoration(
                color: AppColors.borderCardSoft,
                borderRadius: BorderRadius.circular(19.r),
              ),
              child: Icon(PhosphorIcons.wrench(), size: 30.sp, color: AppColors.textPlaceholder),
            ),
            SizedBox(height: 16.h),
            Text(title, style: AppText.sectionTitle()),
            SizedBox(height: 6.h),
            Text(body ?? 'Screen coming in this build',
                textAlign: TextAlign.center, style: AppText.caption()),
          ],
        ),
      ),
    );
    if (!showHeader) return content;
    return Column(
      children: [
        SafeArea(bottom: false, child: Padding(
          padding: EdgeInsets.fromLTRB(14.w, 8.h, 14.w, 0),
          child: const AppHeaderBar(),
        )),
        Expanded(child: content),
      ],
    );
  }
}
