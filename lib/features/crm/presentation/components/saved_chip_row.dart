import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// One saved-view definition (a boolean filter preset).
class SavedView {
  final String key;
  final String label;

  /// The server marked the view invalid (`is_valid: false`). As on the
  /// webapp the chip is greyed with a warning icon and never shows as
  /// applied; a tap still reaches the screen, which says why it can't run.
  final bool invalid;
  const SavedView(this.key, this.label, {this.invalid = false});
}

/// Horizontal, scrollable row of saved-view filter chips (the row under the
/// status tabs on the finance list screens). Toggling a chip is fully
/// functional; a "Clear filters" chip appears once any view is active.
class SavedChipRow extends StatelessWidget {
  const SavedChipRow({
    super.key,
    required this.views,
    required this.active,
    required this.onToggle,
    required this.onClear,
    this.showClearAlways = false,
    this.onRemove,
    this.webappStyle = false,
  });

  /// The webapp's `SavedViewChips` behaviour: an × on every chip that deletes
  /// that saved filter after a confirm. Off by
  /// default so the screens that have not moved over keep their behaviour.
  final bool webappStyle;

  final List<SavedView> views;
  final Set<String> active;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  /// When true the "Clear filters" chip is shown even if no saved view is
  /// active (e.g. manual drawer filters are applied). Defaults to false so
  /// existing callers keep the active-only behaviour.
  final bool showClearAlways;

  /// Deletes a saved view. When set, long-pressing a chip asks for confirmation
  /// first (the webapp's remove-view confirm) and then calls this with its key.
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34.h,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (int i = 0; i < views.length; i++) ...[
              if (i > 0) SizedBox(width: 8.w),
              _chip(context, views[i]),
            ],
            if (active.isNotEmpty || showClearAlways) ...[
              SizedBox(width: 8.w),
              _clearChip(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, SavedView v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(webappStyle ? 'Delete “${v.label}”?' : 'Remove saved view?'),
        content: Text(webappStyle
            ? 'This permanently deletes this saved filter. This can’t be undone.'
            : '"${v.label}" will be removed from your saved filters.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(webappStyle ? 'Delete' : 'Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok == true) onRemove?.call(v.key);
  }

  Widget _chip(BuildContext context, SavedView v) {
    final on = !v.invalid && active.contains(v.key);
    final fg = v.invalid ? AppColors.textPlaceholder : (on ? AppColors.blueBright : AppColors.textLabelAlt);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onToggle(v.key),
      onLongPress: onRemove == null || webappStyle ? null : () => _confirmRemove(context, v),
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        decoration: BoxDecoration(
          color: v.invalid ? AppColors.bgLight : (on ? AppColors.blueSubtle : AppColors.bgChipGrey),
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            v.invalid
                ? Icon(PhosphorIconsFill.warning, size: 13.sp, color: AppColors.warning)
                : Icon(PhosphorIconsFill.bookmarkSimple, size: 13.sp, color: fg),
            SizedBox(width: 5.w),
            Text(v.label, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: fg)),
            // Webapp: every chip carries an × that deletes the saved filter.
            if (webappStyle && onRemove != null) ...[
              SizedBox(width: 4.w),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _confirmRemove(context, v),
                child: Padding(
                  padding: EdgeInsets.all(4.r),
                  child: Icon(PhosphorIconsBold.x, size: 11.sp, color: on ? AppColors.blueBright : AppColors.textLabelAlt),
                ),
              ),
            ] else if (on) ...[
              SizedBox(width: 6.w),
              Icon(PhosphorIconsBold.x, size: 11.sp, color: AppColors.blueBright),
            ],
          ],
        ),
      ),
    );
  }

  Widget _clearChip() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClear,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        decoration: BoxDecoration(
          color: AppColors.blueSubtle,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.xCircle, size: 13.sp, color: AppColors.blueBright),
            SizedBox(width: 5.w),
            Text('Clear filters',
                style: AppText.custom(
                    size: 12.5, weight: FontWeight.w700, color: AppColors.blueBright)),
          ],
        ),
      ),
    );
  }
}
