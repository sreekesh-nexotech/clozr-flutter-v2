import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../crm/domain/entities/view_schema.dart';
import '../../../crm/presentation/components/inline_edit_row.dart';

/// A detail row of a project or project task that a long press turns into an
/// editor — the leads screen's "hold to edit", on Operations fields.
///
/// It reuses the leads [InlineEditRow] (text box in place; sheet for a date,
/// Yes / No or a choice) by describing the field as a one-off column, so the
/// two screens feel and behave the same: save on submit or tap-away, the
/// server's refusal shown beside the box, nothing sent for an unchanged value.
///
/// [apiKey] is the PATCH key, [type] one of `decimal`, `date`, `boolean`, or
/// `string` (with [choices] for a pick-list).
class OpsHoldEditRow extends StatelessWidget {
  const OpsHoldEditRow({
    super.key,
    required this.label,
    required this.display,
    required this.apiKey,
    required this.type,
    required this.rawValue,
    required this.canEdit,
    required this.onSave,
    required this.onBlocked,
    required this.child,
    this.choices = const [],
    this.deniedHint,
    this.editForm = 'Edit',
  });

  final String label;
  final String display;
  final String apiKey;
  final String type;
  final Object? rawValue;
  final List<(String value, String label)> choices;
  final bool canEdit;
  final String? deniedHint;
  final String editForm;

  /// Saves one field; returns null on success, the refusal text otherwise.
  final Future<Object?> Function(String key, Object? value) onSave;
  final void Function(String message) onBlocked;

  /// The row as it looks when it is not being edited.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InlineEditRow(
      label: label,
      display: display,
      column: ViewColumn(
        name: apiKey,
        label: label,
        order: 0,
        type: type,
        inFields: true,
        choices: choices,
      ),
      rawValue: rawValue,
      editForm: editForm,
      canEdit: canEdit,
      deniedHint: deniedHint,
      onSave: onSave,
      onBlocked: onBlocked,
      child: child,
    );
  }
}

/// A row that cannot be edited in place: a long press says where to change it.
class OpsReadOnlyHoldRow extends StatelessWidget {
  const OpsReadOnlyHoldRow(
      {super.key,
      required this.message,
      required this.onBlocked,
      required this.child});

  final String message;
  final void Function(String message) onBlocked;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => onBlocked(message),
        child: child,
      );
}

/// The one-line hint the leads screen shows above its fields.
class OpsHoldEditHint extends StatelessWidget {
  const OpsHoldEditHint({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 4.h, bottom: 6.h),
        child: Row(children: [
          Icon(PhosphorIconsRegular.handTap,
              size: 13.sp, color: AppColors.textPlaceholder),
          SizedBox(width: 6.w),
          Text('Long-press a field to edit it',
              style: AppText.custom(
                  size: 12,
                  weight: FontWeight.w500,
                  color: AppColors.textPlaceholder)),
        ]),
      );
}
