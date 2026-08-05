import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shimmer/shimmer.dart';

import '../../app/theme/app_colors.dart';

/// A single shimmering grey placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = 8});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.borderCardSoft,
        borderRadius: BorderRadius.circular(radius.r),
      ),
    );
  }
}

/// Animated shimmer placeholder for list screens while data loads — makes the
/// loading phase visually distinct from a genuinely empty list. Uses the
/// `shimmer` package (already a dependency) over the app's soft-grey token.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 78,
    this.padding,
    this.itemBuilder,
  });

  final int itemCount;
  final double itemHeight;
  final EdgeInsets? padding;
  final Widget Function(BuildContext context)? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final builder = itemBuilder ?? _cardRow;
    return Shimmer.fromColors(
      baseColor: AppColors.borderCardSoft,
      highlightColor: AppColors.bgScreen,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding ?? EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 24.h),
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(height: 10.h),
        itemBuilder: (context, _) => builder(context),
      ),
    );
  }

  Widget _cardRow(BuildContext context) => SkeletonBox(height: itemHeight.h, radius: 14);

  /// Slim row shape for feeds (notifications, messages, chat).
  static Widget row(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 40.r, height: 40.r, radius: 20),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160.w, height: 12.h),
              SizedBox(height: 8.h),
              SkeletonBox(width: double.infinity, height: 10.h),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shimmer placeholder for a detail screen (header block + a couple of card
/// placeholders) so "not found" no longer flashes during a detail load.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.borderCardSoft,
      highlightColor: AppColors.bgScreen,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 24.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 200.w, height: 22.h),
            SizedBox(height: 10.h),
            SkeletonBox(width: 140.w, height: 14.h),
            SizedBox(height: 22.h),
            SkeletonBox(width: double.infinity, height: 120.h, radius: 16),
            SizedBox(height: 14.h),
            SkeletonBox(width: double.infinity, height: 88.h, radius: 16),
          ],
        ),
      ),
    );
  }
}
