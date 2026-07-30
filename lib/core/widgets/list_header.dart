import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../app/theme/app_colors.dart';

/// The white, non-scrolling header block at the top of every list screen:
/// clears the status bar (56px top pad), lays out its children, and draws the
/// full-bleed hairline under the brand row. Screens pass their header rows as
/// [children].
class ListHeader extends StatelessWidget {
  const ListHeader({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.fromLTRB(18.w, 56.h, 18.w, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// The full-bleed 1px hairline used directly under the brand row (extends past
/// the 18px gutter, matching `margin: 0 -18px`).
class HeaderHairline extends StatelessWidget {
  const HeaderHairline({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bleedWidth = constraints.maxWidth + 36.w;
        return OverflowBox(
          minWidth: bleedWidth,
          maxWidth: bleedWidth,
          minHeight: 1,
          maxHeight: 1,
          alignment: Alignment.center,
          child: Container(
            height: 1,
            color: AppColors.borderCardSoft,
          ),
        );
      },
    );
  }
}
