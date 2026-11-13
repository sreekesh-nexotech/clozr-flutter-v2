import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../application/quote_builder/option_tabs.dart';
import 'qb_kit.dart';

/// The option strip of an alternative-options quote (rulebook v1.7) — the
/// webapp's `OptionTabsBar`: one tab per option (A → C), "Add alternative" up to
/// the template's limit, remove, and which option is the primary (the one that
/// counts toward lead value while the customer decides). Everything outside the
/// line items is shared by every option.
class QuoteOptionTabsBar extends StatelessWidget {
  const QuoteOptionTabsBar({
    super.key,
    required this.tabs,
    required this.active,
    required this.primary,
    required this.max,
    required this.disabled,
    required this.canChangeSet,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
    required this.onMakePrimary,
  });

  final List<OptionTab> tabs;
  final int active;
  final int primary;
  final int max;
  final bool disabled;

  /// Draft groups only: options can be added / removed.
  final bool canChangeSet;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onMakePrimary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QbSectionLabel('Options'),
        const QbHint(
            'The customer receives ONE document with every option and accepts one of them. Party, payment terms, validity and the other details are shared; each option has its own items. Only the primary option counts toward the lead’s value until the customer chooses.'),
        SizedBox(height: 10.h),
        Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < tabs.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _tab('Option ${optionLabel(i)}',
                      on: i == active,
                      star: i == primary,
                      onTap: () => onSelect(i)),
                  if (canChangeSet && !disabled && tabs.length > 1)
                    Semantics(
                      label: 'Remove option ${optionLabel(i)}',
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onRemove(i),
                        child: Padding(
                          padding: EdgeInsets.all(6.r),
                          child: Icon(PhosphorIconsBold.x,
                              size: 13.sp, color: AppColors.textPlaceholder),
                        ),
                      ),
                    ),
                ]),
              if (canChangeSet && !disabled && tabs.length < max)
                _tab('Add alternative',
                    on: false,
                    star: false,
                    dashed: true,
                    icon: PhosphorIconsBold.plus,
                    onTap: onAdd),
            ]),
        if (!disabled && tabs.length > 1 && active != primary) ...[
          SizedBox(height: 8.h),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Option ${optionLabel(active)} is an alternative. ',
                style: AppText.custom(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.textMuted)),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onMakePrimary(active),
              child: Text('Make it the primary option',
                  style: AppText.custom(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.navy)),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _tab(String label,
      {required bool on,
      required bool star,
      required VoidCallback onTap,
      bool dashed = false,
      IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: on ? AppColors.blueSubtle : AppColors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
              color: on ? AppColors.navy : const Color(0xFFE6E7EA), width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13.sp, color: AppColors.textLabelAlt),
            SizedBox(width: 5.w)
          ],
          Text(label,
              style: AppText.custom(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: on ? AppColors.navy : AppColors.textLabelAlt)),
          if (star) ...[
            SizedBox(width: 5.w),
            Tooltip(
                message: 'Primary option',
                child: Icon(PhosphorIconsFill.star,
                    size: 12.sp, color: AppColors.navy)),
          ],
        ]),
      ),
    );
  }
}
