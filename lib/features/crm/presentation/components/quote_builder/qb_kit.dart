import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';

/// Small building blocks shared by the quote builder's sections, in the look
/// the New quote screen already had (uppercase section labels, 44h bordered
/// boxes, blue-tinted selected chips) so the parity work does not change how
/// the screen feels.

/// "LINE ITEMS"-style section label.
class QbSectionLabel extends StatelessWidget {
  const QbSectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2.w, 14.h, 2.w, 12.h),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A field label with the red required mark.
class QbFieldLabel extends StatelessWidget {
  const QbFieldLabel(this.label, {super.key, this.required = false});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Flexible(
        child: Text(label, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
      ),
      if (required) Text(' *', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
    ]);
  }
}

/// A muted helper / error line under a field.
class QbHint extends StatelessWidget {
  const QbHint(this.text, {super.key, this.error = false, this.align = TextAlign.start});
  final String text;
  final bool error;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 5.h),
        child: Text(text,
            textAlign: align,
            style: AppText.custom(
                size: 11.5, weight: FontWeight.w500, color: error ? AppColors.error : AppColors.textPlaceholder)),
      );
}

enum QbTone { info, warning, danger }

/// The web builder's `BuilderNotice`: a tinted, icon-led message box.
class QbNotice extends StatelessWidget {
  const QbNotice({super.key, required this.tone, required this.children, this.icon, this.action});
  final QbTone tone;
  final List<Widget> children;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      QbTone.info => (AppColors.tintBlue, AppColors.navy),
      QbTone.warning => (AppColors.tintAmber, AppColors.warningDeep),
      QbTone.danger => (AppColors.tintRed, AppColors.error),
    };
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? PhosphorIconsRegular.info, size: 16.sp, color: fg),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) SizedBox(height: 4.h),
                  children[i],
                ],
                if (action != null) ...[SizedBox(height: 8.h), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Body text for a [QbNotice].
Text qbNoticeText(String text, {bool strong = false, bool muted = false}) => Text(text,
    style: AppText.custom(
        size: 12.5,
        weight: strong ? FontWeight.w700 : FontWeight.w500,
        color: muted ? AppColors.textMuted : AppColors.textBody));

/// The screen's chip row (single choice).
class QbChipField extends StatelessWidget {
  const QbChipField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.required = false,
    this.disabled = false,
  });

  final String label;
  final List<(String value, String label)> options;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool required;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QbFieldLabel(label, required: required),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final o in options)
              QbChip(
                label: o.$2,
                selected: selected == o.$1,
                onTap: disabled ? null : () => onSelect(o.$1),
              ),
          ],
        ),
      ],
    );
  }
}

class QbChip extends StatelessWidget {
  const QbChip({super.key, required this.label, required this.selected, this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dim = onTap == null && !selected;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38.h,
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: selected ? AppColors.blueSubtle : (dim ? AppColors.bgChipGrey : AppColors.white),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: selected ? const Color(0xFFA6D1FF) : const Color(0xFFE6E7EA),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14.sp, color: selected ? AppColors.navy : AppColors.textLabelAlt),
            SizedBox(width: 6.w),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.custom(
                    size: 13,
                    weight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? AppColors.navy : AppColors.textLabelAlt)),
          ),
        ]),
      ),
    );
  }
}

/// A compact bordered input (quantity, price, HSN, term …).
class QbBox extends StatelessWidget {
  const QbBox({
    super.key,
    required this.controller,
    this.hint,
    this.onChanged,
    this.error = false,
    this.enabled = true,
    this.numeric = false,
    this.align = TextAlign.start,
    this.inputFormatters,
    this.suffix,
    this.muted = false,
    this.focusNode,
    this.height,
    this.maxLength,
  });

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final bool error;
  final bool enabled;
  final bool numeric;
  final TextAlign align;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffix;

  /// Grey text — an untouched catalog price.
  final bool muted;
  final FocusNode? focusNode;
  final double? height;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height ?? 44.h,
      padding: EdgeInsets.only(left: 10.w, right: suffix == null ? 10.w : 2.w),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? AppColors.white : AppColors.bgChipGrey,
        borderRadius: BorderRadius.circular(11.r),
        border: Border.all(color: error ? AppColors.error : AppColors.borderInput, width: 1.5),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            textAlign: align,
            maxLength: maxLength,
            keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            style: AppText.custom(
                size: 13.5, weight: FontWeight.w600, color: muted ? AppColors.textMuted : AppColors.textBody),
            cursorColor: AppColors.blueBright,
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              border: InputBorder.none,
              hintText: hint,
              hintStyle: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
            ),
          ),
        ),
        if (suffix != null) suffix!,
      ]),
    );
  }
}

/// A tappable picker box showing a value or a placeholder, with a caret.
class QbPickerBox extends StatelessWidget {
  const QbPickerBox({
    super.key,
    required this.text,
    required this.placeholder,
    this.onTap,
    this.error = false,
    this.icon,
    this.height,
    this.trailing,
  });

  final String text;
  final String placeholder;
  final VoidCallback? onTap;
  final bool error;
  final IconData? icon;
  final double? height;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final empty = text.isEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: height ?? 44.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.bgChipGrey : AppColors.white,
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: error ? AppColors.error : AppColors.borderInput, width: 1.5),
        ),
        child: Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 15.sp, color: AppColors.textPlaceholder),
            SizedBox(width: 8.w),
          ],
          Expanded(
            child: Text(empty ? placeholder : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.custom(
                    size: 13.5,
                    weight: empty ? FontWeight.w500 : FontWeight.w600,
                    color: empty ? AppColors.textPlaceholder : AppColors.textBody)),
          ),
          if (trailing != null) trailing!,
          if (onTap != null) Icon(PhosphorIconsBold.caretDown, size: 12.sp, color: AppColors.textMuted2),
        ]),
      ),
    );
  }
}

/// A dashed-look "Add …" button.
class QbAddButton extends StatelessWidget {
  const QbAddButton({super.key, required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.borderInput, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14.sp, color: AppColors.textLabelAlt),
          SizedBox(width: 7.w),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
          ),
        ]),
      ),
    );
  }
}

/// A small square icon button (remove, move, reset).
class QbIconButton extends StatelessWidget {
  const QbIconButton({super.key, required this.icon, this.onTap, this.danger = false, this.tooltip, this.size});
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;
  final String? tooltip;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final s = size ?? 32.w;
    final child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: s,
        height: s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9.r),
          border: Border.all(color: danger ? const Color(0xFFF3C1C1) : const Color(0xFFE6E7EA)),
        ),
        child: Icon(icon,
            size: 15.sp,
            color: onTap == null ? AppColors.textPlaceholder : (danger ? AppColors.error : AppColors.textLabelAlt)),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// Picks one string from a short list in a bottom sheet with the app chrome.
Future<String?> qbPickOne(
  BuildContext context, {
  required String title,
  required List<(String value, String label)> options,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (ctx) => Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
      decoration: BoxDecoration(
        color: AppColors.bgApp,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 22.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
          SizedBox(height: 10.h),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final o in options)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(ctx).pop(o.$1),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 13.h),
                      child: Row(children: [
                        Expanded(
                          child: Text(o.$2,
                              style: AppText.custom(
                                  size: 14,
                                  weight: o.$1 == selected ? FontWeight.w700 : FontWeight.w600,
                                  color: o.$1 == selected ? AppColors.navy : AppColors.textPrimary)),
                        ),
                        if (o.$1 == selected) Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.success),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Keeps a controller's text in step with a value set from outside (a reset,
/// a price flip) without fighting the user's own typing.
void qbSync(TextEditingController c, String value) {
  if (c.text != value) {
    c.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
  }
}
