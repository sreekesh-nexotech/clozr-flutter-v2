import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// A labelled form field. `40px` input by default, 8px radius, inset 1px border
/// (`#DADADA`). Set [multiline] for a textarea. Set [readOnly] + [onTap] to use
/// it as a picker trigger (shows a caret).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.value,
    this.required = false,
    this.multiline = false,
    this.readOnly = false,
    this.onTap,
    this.onChanged,
    this.keyboardType,
    this.suffixIcon,
    this.errorText,
    this.prefix,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? value; // for read-only / picker display
  final bool required;
  final bool multiline;
  final bool readOnly;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final IconData? suffixIcon;
  final String? errorText;

  /// Rendered inside the border, ahead of the input, and **not** part of the
  /// controller's text — a `+91` here is shown, never typed over or submitted.
  final String? prefix;

  /// Keystroke-level constraints (digits only, a length cap). `keyboardType`
  /// alone does not restrict anything: it picks the on-screen keyboard, which
  /// still offers `+ * #`, and pasting bypasses it entirely.
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final showCaret = readOnly && onTap != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            if (required)
              Text(' *', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
          ],
        ),
        SizedBox(height: 7.h),
        GestureDetector(
          onTap: onTap,
          child: AbsorbPointer(
            absorbing: readOnly,
            child: Container(
              constraints: BoxConstraints(minHeight: multiline ? 88.h : 44.h),
              padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: multiline ? 12.h : 0),
              alignment: multiline ? Alignment.topLeft : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(
                  color: errorText != null ? AppColors.error : AppColors.borderInput,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  if (prefix != null) ...[
                    Text(prefix!, style: AppText.body(color: AppColors.textMuted)),
                    SizedBox(width: 6.w),
                  ],
                  Expanded(
                    child: readOnly
                        ? Text(
                            value?.isNotEmpty == true ? value! : (hint ?? ''),
                            style: value?.isNotEmpty == true
                                ? AppText.body()
                                : AppText.body(color: AppColors.textPlaceholder),
                          )
                        : TextField(
                            controller: controller,
                            onChanged: onChanged,
                            keyboardType: keyboardType,
                            inputFormatters: inputFormatters,
                            minLines: multiline ? 3 : 1,
                            maxLines: multiline ? 6 : 1,
                            style: AppText.body(),
                            cursorColor: AppColors.blueBright,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: hint,
                              hintStyle: AppText.body(color: AppColors.textPlaceholder),
                            ),
                          ),
                  ),
                  if (suffixIcon != null) Icon(suffixIcon, size: 17.sp, color: AppColors.textMuted),
                  if (showCaret && suffixIcon == null)
                    Icon(PhosphorIconsBold.caretDown, size: 14.sp, color: AppColors.textPlaceholder),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          SizedBox(height: 5.h),
          Text(errorText!, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.error)),
        ],
      ],
    );
  }
}

/// A grouped form section: bold section label + a white card wrapping fields.
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.title, required this.children, this.gap = 14});
  final String title;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 2.w, bottom: 10.h),
          child: Text(title,
              style: AppText.custom(size: 13, weight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap.h),
          children[i],
        ],
      ],
    );
  }
}
