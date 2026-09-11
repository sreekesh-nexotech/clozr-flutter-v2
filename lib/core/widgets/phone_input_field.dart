import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../models/country_code.dart';
import '../network/providers/country_codes_provider.dart';
import 'country_code_picker_sheet.dart';
import 'phone_controller.dart';

/// A contact-number field with a tappable country-code chip — the shared
/// replacement for every `AppTextField(prefix: PhoneFormat.dialCode, …)`
/// phone box in the app, now backed by `GET /crm/country-codes/` instead of a
/// hardcoded `+91`.
///
/// Visually matches [AppTextField]'s label/border/error chrome exactly (same
/// radius, padding, colors) so swapping one in for the other is invisible —
/// it just gains a flag instead of a bare "+91" and enforces the selected
/// country's digit count instead of always assuming 10.
class PhoneInputField extends ConsumerStatefulWidget {
  const PhoneInputField({
    super.key,
    required this.label,
    required this.controller,
    this.required = false,
    this.hint,
    this.errorText,
    this.onChanged,
  });

  final String label;
  final PhoneController controller;
  final bool required;
  final String? hint;
  final String? errorText;

  /// Fires on every keystroke *and* every country change — a screen tracking
  /// "has this field been touched" for its own validation state wants both.
  final VoidCallback? onChanged;

  @override
  ConsumerState<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends ConsumerState<PhoneInputField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant PhoneInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _pickCountry(List<CountryCode> countries) async {
    final picked = await showCountryCodePicker(
      context: context,
      countries: countries,
      selectedIso2: widget.controller.iso2,
    );
    if (picked != null) widget.controller.selectCountry(picked);
  }

  @override
  Widget build(BuildContext context) {
    final countriesAsync = ref.watch(countryCodesProvider);
    final countries = countriesAsync.valueOrNull ?? const <CountryCode>[];
    // One-shot: only actually seeds the first time the catalog has real rows,
    // per `PhoneController.seedOnce`'s own guard.
    if (countries.isNotEmpty) widget.controller.seedOnce(countries);

    final current = countries.where((c) => c.iso2 == widget.controller.iso2).firstOrNull;
    final flag = current?.flag ?? '';
    final dialCode = current?.dialCode ?? widget.controller.dialCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label,
                style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            if (widget.required)
              Text(' *', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
          ],
        ),
        SizedBox(height: 7.h),
        Container(
          constraints: BoxConstraints(minHeight: 44.h),
          padding: EdgeInsets.symmetric(horizontal: 13.w),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(11.r),
            border: Border.all(
              color: widget.errorText != null ? AppColors.error : AppColors.borderInput,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: countries.isEmpty ? null : () => _pickCountry(countries),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (flag.isNotEmpty) ...[
                      Text(flag, style: TextStyle(fontSize: 15.sp)),
                      SizedBox(width: 5.w),
                    ],
                    Text(dialCode, style: AppText.body(color: AppColors.textMuted)),
                    SizedBox(width: 3.w),
                    Icon(PhosphorIconsBold.caretDown, size: 12.sp, color: AppColors.textPlaceholder),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Container(width: 1, height: 20.h, color: AppColors.borderCardSoft),
              SizedBox(width: 8.w),
              Expanded(
                child: TextField(
                  controller: widget.controller.digits,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.controller.rule.max),
                  ],
                  style: AppText.body(),
                  cursorColor: AppColors.blueBright,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: AppText.body(color: AppColors.textPlaceholder),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.errorText != null) ...[
          SizedBox(height: 5.h),
          Text(widget.errorText!,
              style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.error)),
        ],
      ],
    );
  }
}
