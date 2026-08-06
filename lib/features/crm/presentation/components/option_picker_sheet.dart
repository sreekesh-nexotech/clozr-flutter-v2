import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../domain/entities/crm_catalog.dart';
import '../sheets/add_sheet_kit.dart';

/// Picks one or several options from a catalog.
///
/// Shared by the schema-driven lead form's foreign-key/many-to-many fields and
/// the lead detail screen's Assignees control, so both behave the same and
/// there is one place that knows what "selected" looks like.
///
/// Returns the chosen ids, or null when dismissed without confirming — which a
/// caller must treat as "no change", not "cleared".
Future<Set<String>?> showOptionPicker({
  required BuildContext context,
  required String title,
  required List<CatalogOption> options,
  required Set<String> selected,
  bool multi = false,
  String? emptyNote,
}) {
  return showClozrSheet<Set<String>>(
    context: context,
    builder: (_) => _OptionPickerSheet(
      title: title,
      options: options,
      selected: selected,
      multi: multi,
      emptyNote: emptyNote,
    ),
  );
}

class _OptionPickerSheet extends StatefulWidget {
  const _OptionPickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.multi,
    this.emptyNote,
  });

  final String title;
  final List<CatalogOption> options;
  final Set<String> selected;
  final bool multi;

  /// Shown instead of the list when there is nothing to choose from.
  final String? emptyNote;

  @override
  State<_OptionPickerSheet> createState() => _OptionPickerSheetState();
}

class _OptionPickerSheetState extends State<_OptionPickerSheet> {
  late final Set<String> _picked = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final empty = widget.options.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: widget.title, onClose: () => Navigator.of(context).pop()),
        if (empty)
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
            child: Text(
              widget.emptyNote ?? 'Nothing to choose from yet.',
              textAlign: TextAlign.center,
              style: AppText.custom(
                      size: 13, weight: FontWeight.w500, color: AppColors.textMuted)
                  .copyWith(height: 1.5),
            ),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 12.h),
              children: [
                for (final o in widget.options)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (widget.multi) {
                        setState(() => _picked.contains(o.id)
                            ? _picked.remove(o.id)
                            : _picked.add(o.id));
                        return;
                      }
                      Navigator.of(context).pop({o.id});
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 11.h, horizontal: 6.w),
                      child: Row(
                        children: [
                          if (o.color != null) ...[
                            Container(
                              width: 9.w,
                              height: 9.w,
                              decoration: BoxDecoration(
                                  color: o.color, shape: BoxShape.circle),
                            ),
                            SizedBox(width: 10.w),
                          ],
                          Expanded(child: Text(o.name, style: AppText.bodyStrong())),
                          if (_picked.contains(o.id))
                            Icon(PhosphorIconsBold.check,
                                size: 19.sp, color: AppColors.success),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (widget.multi && !empty)
          SheetSubmitBar(
            label: 'Done',
            icon: PhosphorIconsBold.check,
            onTap: () => Navigator.of(context).pop(_picked),
          ),
      ],
    );
  }
}
