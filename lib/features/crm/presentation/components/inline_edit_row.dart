import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../application/record_rows.dart';
import '../../domain/entities/view_schema.dart';

/// A detail-card information row that a long press turns into a text box.
///
/// The read-only appearance is the caller's ([child]) — the detail screens do
/// not agree on it (`DetailInfoRow`, `MetaRow`, a task's icon row) and this
/// widget is not the place to unify them. Only the editing state is shared, so
/// the gesture, the seeding, the commit rules and the refusal messages cannot
/// drift between five screens.
///
/// Nothing here decides *what* is editable: [column] carries the org's own
/// answer, and [inlineEditHint] turns a refusal into something to say.
class InlineEditRow extends StatefulWidget {
  const InlineEditRow({
    super.key,
    required this.label,
    required this.display,
    required this.column,
    required this.rawValue,
    required this.editForm,
    required this.onSave,
    required this.onBlocked,
    required this.child,
    this.writeKey,
  });

  final String label;

  /// What the row shows now — the seed when the record carries no raw value.
  final String display;

  /// The column behind the row. Null for a screen's built-in fallback rows,
  /// which no org layout names.
  final ViewColumn? column;

  /// The **stored** value, straight off the record. Display text is formatted
  /// (`₹18L`, `12 Aug 2026`) and posting that back would be nonsense.
  final Object? rawValue;

  /// Where a picker-only field can be changed instead ("Edit quote"), quoted
  /// back to the user when they long-press one.
  final String editForm;

  /// Saves one field. [value] is already coerced for the column's type.
  final Future<void> Function(String key, Object? value) onSave;

  /// Says why nothing opened. The screens route this to their toast.
  final void Function(String message) onBlocked;

  /// The row as it looks when it is not being edited.
  final Widget child;

  /// The API key this column is written under, when it differs from its name
  /// (a lead's `status` is written as `status_id`).
  final String Function(ViewColumn column)? writeKey;

  @override
  State<InlineEditRow> createState() => _InlineEditRowState();
}

class _InlineEditRowState extends State<InlineEditRow> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _editing = false;

  /// What the box opened with, so committing an untouched field writes nothing.
  String _seed = '';

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _begin() {
    final hint = inlineEditHint(widget.column, editForm: widget.editForm);
    if (hint != null) {
      widget.onBlocked(hint);
      return;
    }
    final raw = widget.rawValue;
    _seed = raw == null ? (widget.display == '—' ? '' : widget.display) : '$raw';
    setState(() {
      _editing = true;
      _ctrl.text = _seed;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    });
    _focus.requestFocus();
  }

  Future<void> _commit() async {
    // Submitting also drops focus, so both paths land here for one edit.
    if (!_editing) return;
    final column = widget.column!;
    final text = _ctrl.text.trim();
    setState(() => _editing = false);
    // Tapping away from a field nobody changed is not an edit.
    if (text == _seed.trim()) return;
    final value = schemaWriteValue(column.type, text);
    if (identical(value, absentValue)) return;
    final key = widget.writeKey?.call(column) ?? column.name;
    await widget.onSave(key, value);
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _begin,
        child: widget.child,
      );
    }
    final column = widget.column!;
    final numeric =
        const {'decimal', 'integer', 'number', 'float'}.contains(column.type);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5))),
      ),
      child: Row(
        children: [
          Text(widget.label,
              style: AppText.custom(
                  size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
          SizedBox(width: 14.w),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              textAlign: TextAlign.right,
              maxLines: column.type == 'text' ? null : 1,
              keyboardType: numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              textInputAction: column.type == 'text'
                  ? TextInputAction.newline
                  : TextInputAction.done,
              style: AppText.custom(
                  size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                filled: true,
                fillColor: AppColors.bgChipGrey,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) => _commit(),
            ),
          ),
        ],
      ),
    );
  }
}
