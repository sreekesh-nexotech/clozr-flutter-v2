import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../application/record_rows.dart';
import 'field_value_sheet.dart';
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
    this.canEdit = true,
    this.deniedHint,
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
  ///
  /// Returns null on success, or the refusal text (the server's rule for that
  /// field): the box then stays open with the typed text and the message
  /// beside it, as the webapp's editors do. Returning a `Future<void>` is
  /// also fine — it reads as success.
  final Future<Object?> Function(String key, Object? value) onSave;

  /// Says why nothing opened. The screens route this to their toast.
  final void Function(String message) onBlocked;

  /// The row as it looks when it is not being edited.
  final Widget child;

  /// The API key this column is written under, when it differs from its name
  /// (a lead's `status` is written as `status_id`).
  final String Function(ViewColumn column)? writeKey;

  /// Whether the signed-in role may edit this record at all. False → a long
  /// press opens nothing and says why (webapp: the row renders read-only).
  final bool canEdit;

  /// What a long press says when [canEdit] is false.
  final String? deniedHint;

  @override
  State<InlineEditRow> createState() => _InlineEditRowState();
}

class _InlineEditRowState extends State<InlineEditRow> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _editing = false;
  bool _saving = false;

  /// The server's refusal for the text typed, shown under the box.
  String? _error;

  /// The text that was refused, so tapping away from it cancels instead of
  /// re-sending the same value.
  String? _failedText;

  /// What the box opened with, so committing an untouched field writes nothing.
  String _seed = '';

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    if (!widget.canEdit) {
      widget.onBlocked(widget.deniedHint ??
          "You don't have permission to edit records here. Ask a workspace admin.");
      return;
    }
    final hint = inlineEditHint(widget.column, editForm: widget.editForm);
    if (hint != null) {
      widget.onBlocked(hint);
      return;
    }
    final column = widget.column!;
    final kind = inlineKindOf(column);
    final raw = widget.rawValue;
    if (kind != InlineKind.text &&
        kind != InlineKind.multiline &&
        kind != InlineKind.number) {
      // Date, Yes / No and choices need a picker, not a text box.
      final result = await showFieldValueSheet(context,
          label: widget.label,
          kind: kind,
          initial: raw,
          options: column.choices);
      if (result == null || !mounted) return;
      final refused = await widget.onSave(
          widget.writeKey?.call(column) ?? column.name, result.value);
      if (refused is String && refused.isNotEmpty && mounted) {
        widget.onBlocked(refused);
      }
      return;
    }
    _seed =
        raw == null ? (widget.display == '—' ? '' : widget.display) : '$raw';
    setState(() {
      _editing = true;
      _error = null;
      _failedText = null;
      _ctrl.text = _seed;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    });
    _focus.requestFocus();
  }

  Future<void> _commit() async {
    // Submitting also drops focus, so both paths land here for one edit.
    if (!_editing || _saving) return;
    final column = widget.column!;
    final text = _ctrl.text.trim();
    // Tapping away from a field nobody changed — or from one the server just
    // refused — is not an edit.
    if (text == _seed.trim() || text == _failedText) {
      setState(() {
        _editing = false;
        _error = null;
      });
      return;
    }
    // Webapp `NOT_A_NUMBER`: commas and spaces are fine, anything else is
    // refused before a round trip and the box stays open.
    final numeric =
        const {'decimal', 'integer', 'number', 'float'}.contains(column.type);
    if (numeric &&
        text.isNotEmpty &&
        num.tryParse(text.replaceAll(RegExp(r'[,\s]'), '')) == null) {
      setState(() => _error = 'Enter a number, e.g. 500000 or 12.5.');
      _focus.requestFocus();
      return;
    }
    final value = schemaWriteValue(
        column.type, numeric ? text.replaceAll(RegExp(r'[,\s]'), '') : text);
    if (identical(value, absentValue)) {
      setState(() => _editing = false);
      return;
    }
    final key = widget.writeKey?.call(column) ?? column.name;
    setState(() {
      _saving = true;
      _error = null;
    });
    final refused = await widget.onSave(key, value);
    if (!mounted) return;
    if (refused is String && refused.isNotEmpty) {
      setState(() {
        _saving = false;
        _error = refused;
        _failedText = text;
      });
      _focus.requestFocus();
      return;
    }
    setState(() {
      _saving = false;
      _editing = false;
    });
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(widget.label,
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w500,
                      color: AppColors.textMuted)),
              SizedBox(width: 14.w),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  autofocus: true,
                  textAlign: TextAlign.right,
                  maxLines:
                      column.type == 'text' || column.customType == 'textarea'
                          ? null
                          : 1,
                  // Webapp: a single-line custom text field holds at most 255
                  // characters — typing stops there rather than being cut on save.
                  maxLength: column.isCustom && column.customType == 'text'
                      ? ViewColumn.customTextMax
                      : null,
                  buildCounter: column.isCustom && column.customType == 'text'
                      ? (ctx,
                              {required currentLength,
                              required isFocused,
                              maxLength}) =>
                          Text('$currentLength/$maxLength',
                              style: AppText.custom(
                                  size: 11,
                                  weight: FontWeight.w500,
                                  color: AppColors.textMuted))
                      : null,
                  keyboardType: numeric
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : column.type == 'text' || column.customType == 'textarea'
                          ? TextInputType.multiline
                          : TextInputType.text,
                  textInputAction:
                      column.type == 'text' || column.customType == 'textarea'
                          ? TextInputAction.newline
                          : TextInputAction.done,
                  style: AppText.custom(
                      size: 13.5,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimary),
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
          if (_error != null)
            Padding(
              padding: EdgeInsets.only(top: 4.h, left: 4.w),
              child: Text(_error!,
                  textAlign: TextAlign.right,
                  style: AppText.custom(
                      size: 12,
                      weight: FontWeight.w500,
                      color: AppColors.error)),
            ),
        ],
      ),
    );
  }
}
