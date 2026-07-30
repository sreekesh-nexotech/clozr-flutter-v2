import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// One entry on a detail-screen activity timeline.
class ActivityItem {
  final IconData icon;
  final Color tone;
  final Color bg;
  final String title;
  final String sub;
  final String time;

  const ActivityItem({
    required this.icon,
    required this.tone,
    required this.bg,
    required this.title,
    required this.sub,
    this.time = '',
  });
}

/// A vertical activity/timeline list: coloured icon chip with a connector line,
/// title, sub and optional time. Used on every CRM detail screen.
class ActivityTimeline extends StatelessWidget {
  const ActivityTimeline({super.key, required this.items});
  final List<ActivityItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < items.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 34.w,
                      height: 34.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: items[i].bg, shape: BoxShape.circle),
                      child: Icon(items[i].icon, size: 16.sp, color: items[i].tone),
                    ),
                    if (i < items.length - 1)
                      Expanded(
                        child: Container(width: 1.5.w, color: AppColors.borderCardSoft, constraints: BoxConstraints(minHeight: 12.h)),
                      ),
                  ],
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(0, 6.h, 0, 16.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(items[i].title, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text(items[i].sub, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2)),
                        if (items[i].time.isNotEmpty) ...[
                          SizedBox(height: 3.h),
                          Text(items[i].time, style: AppText.micro()),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Underline tab strip used inside detail activity cards (Tasks / Call log / …).
/// Active tab: navy 700 label with a 2.5px navy underline.
class DetailUnderlineTabs extends StatelessWidget {
  const DetailUnderlineTabs({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE6E7EA), width: 1.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (int i = 0; i < labels.length; i++) ...[
              if (i > 0) SizedBox(width: 20.w),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Container(
                  padding: EdgeInsets.only(top: 4.h, bottom: 12.h),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: index == i ? AppColors.navy : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: AppText.custom(
                      size: 14,
                      weight: index == i ? FontWeight.w700 : FontWeight.w500,
                      color: index == i ? AppColors.navy : AppColors.textPlaceholder,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A label → value row with a bottom hairline, used in the "information" cards.
class DetailInfoRow extends StatelessWidget {
  const DetailInfoRow({super.key, required this.label, required this.value, this.last = false});
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F5))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
          SizedBox(width: 14.w),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// The centered "empty tab" placeholder used inside detail activity cards.
class DetailTabEmpty extends StatelessWidget {
  const DetailTabEmpty({super.key, required this.icon, required this.title, required this.body, this.cta});
  final IconData icon;
  final String title;
  final String body;
  final Widget? cta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 34.h, 20.w, 20.h),
      child: Column(
        children: [
          Container(
            width: 56.w,
            height: 56.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(16.r)),
            child: Icon(icon, size: 26.sp, color: AppColors.textPlaceholder),
          ),
          SizedBox(height: 14.h),
          Text(title, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary), textAlign: TextAlign.center),
          SizedBox(height: 5.h),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 220.w),
            child: Text(body,
                textAlign: TextAlign.center,
                style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted).copyWith(height: 1.5)),
          ),
          if (cta != null) ...[SizedBox(height: 16.h), cta!],
        ],
      ),
    );
  }
}
