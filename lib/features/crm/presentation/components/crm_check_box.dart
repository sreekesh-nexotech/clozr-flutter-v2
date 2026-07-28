import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';

/// The circular-square completion checkbox used on task / follow-up cards and
/// the lead-detail tabs. Matches the prototype's `ck()` helper: 26×26, 8px
/// radius, green fill when done else a 1.5px grey ring.
class CrmCheckBox extends StatelessWidget {
  const CrmCheckBox({super.key, required this.done, required this.onTap, this.size = 26});

  final bool done;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size.w,
        height: size.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done ? AppColors.success : AppColors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: done ? null : Border.all(color: const Color(0xFFC7CBD3), width: 1.5),
        ),
        child: Icon(PhosphorIconsBold.check, size: (size * 0.54).sp, color: done ? AppColors.white : Colors.transparent),
      ),
    );
  }
}
