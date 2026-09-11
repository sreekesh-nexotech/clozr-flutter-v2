import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../models/country_code.dart';
import 'app_bottom_sheet.dart';

/// Picks one [CountryCode] for a phone field's dial-code chip. Search-first —
/// the catalog is every dialable country, easily 190+ rows, so scrolling to
/// find one unaided is not realistic the way it is for a short org catalog.
Future<CountryCode?> showCountryCodePicker({
  required BuildContext context,
  required List<CountryCode> countries,
  required String selectedIso2,
}) {
  return showClozrSheet<CountryCode>(
    context: context,
    builder: (_) => _CountryCodePickerSheet(countries: countries, selectedIso2: selectedIso2),
  );
}

class _CountryCodePickerSheet extends StatefulWidget {
  const _CountryCodePickerSheet({required this.countries, required this.selectedIso2});

  final List<CountryCode> countries;
  final String selectedIso2;

  @override
  State<_CountryCodePickerSheet> createState() => _CountryCodePickerSheetState();
}

class _CountryCodePickerSheetState extends State<_CountryCodePickerSheet> {
  final _query = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.countries
        : widget.countries
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.dialCode.contains(q) ||
                c.iso2.toLowerCase().contains(q))
            .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Country code', onClose: () => Navigator.of(context).pop()),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 10.h),
          child: Container(
            height: 40.h,
            padding: EdgeInsets.symmetric(horizontal: 13.w),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(11.r),
              border: Border.all(color: AppColors.borderInput, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.magnifyingGlass, size: 16.sp, color: AppColors.textMuted),
                SizedBox(width: 8.w),
                Expanded(
                  child: TextField(
                    controller: _query,
                    autofocus: false,
                    onChanged: (v) => setState(() => _search = v),
                    style: AppText.body(),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search country or code…',
                      hintStyle: AppText.body(color: AppColors.textPlaceholder),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
            child: Text(
              'No country matches "${_search.trim()}".',
              textAlign: TextAlign.center,
              style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)
                  .copyWith(height: 1.5),
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 20.h),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final c = filtered[i];
                final selected = c.iso2 == widget.selectedIso2;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(c),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 11.h, horizontal: 6.w),
                    child: Row(
                      children: [
                        Text(c.flag, style: TextStyle(fontSize: 18.sp)),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Text(c.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong()),
                        ),
                        SizedBox(width: 8.w),
                        Text(c.dialCode,
                            style: AppText.custom(
                                size: 13, weight: FontWeight.w600, color: AppColors.textMuted)),
                        if (selected) ...[
                          SizedBox(width: 10.w),
                          Icon(PhosphorIconsBold.check, size: 17.sp, color: AppColors.success),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
