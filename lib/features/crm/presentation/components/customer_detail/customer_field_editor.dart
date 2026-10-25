import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../../core/widgets/app_text_field.dart';
import '../../../../../core/widgets/primary_button.dart';
import '../../../application/customer_detail_rules.dart';
import '../../sheets/add_sheet_kit.dart' show pickSheetDate, sheetDateLabel, sheetIsoDate;

/// Saves one patch. Null on success; otherwise the message to show under the
/// field and whether it was a stale-record refusal (412) that offers Reload.
typedef CustomerFieldSave = Future<({String message, bool stale})?> Function(Map<String, dynamic> patch);

/// The webapp's inline field editor as a sheet: tap a row, edit, Save. A
/// refused save keeps the sheet open with the typed value and the server's
/// message under the field; a 412 reads "Changed elsewhere — …" with Reload,
/// after which Save applies the same value to the latest version.
Future<void> showCustomerFieldEditor(
  BuildContext context, {
  required CustomerInfoField field,
  required CustomerFieldSave onSave,
  required Future<void> Function() onReload,
}) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _FieldEditorSheet(field: field, onSave: onSave, onReload: onReload),
  );
}

class _FieldEditorSheet extends StatefulWidget {
  const _FieldEditorSheet({required this.field, required this.onSave, required this.onReload});

  final CustomerInfoField field;
  final CustomerFieldSave onSave;
  final Future<void> Function() onReload;

  @override
  State<_FieldEditorSheet> createState() => _FieldEditorSheetState();
}

class _FieldEditorSheetState extends State<_FieldEditorSheet> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.field.editValue);
  late String _value = widget.field.editValue;
  String? _error;
  bool _stale = false;
  bool _saving = false;
  bool _reloading = false;
  bool _reloaded = false;

  CustomerInfoField get f => widget.field;

  bool get _isText => const {
        InfoEditKind.text,
        InfoEditKind.multiline,
        InfoEditKind.email,
        InfoEditKind.phone,
        InfoEditKind.number,
      }.contains(f.kind);

  /// Text and date editors show the message in the field's own error slot;
  /// a stale refusal needs the Reload action beside it, so it gets the row.
  bool get _errorInField => (_isText || f.kind == InfoEditKind.date) && !_stale;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final input = _isText ? _ctrl.text : _value;
    final local = customerFieldInputError(f, input);
    if (local != null) {
      setState(() {
        _error = local;
        _stale = false;
      });
      return;
    }
    // Nothing changed → nothing to write.
    if (input.trim() == f.editValue.trim() && !_reloaded) {
      Navigator.of(context).pop();
      return;
    }
    final patch = customerFieldPatch(f, input);
    if (patch == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final err = await widget.onSave(patch);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = err.message;
      _stale = err.stale;
    });
  }

  Future<void> _reload() async {
    setState(() => _reloading = true);
    await widget.onReload();
    if (!mounted) return;
    setState(() {
      _reloading = false;
      _reloaded = true;
      _stale = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: f.label),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 8.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _editor(),
                  if (_error != null && !_errorInField) ...[
                    SizedBox(height: 8.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(PhosphorIconsRegular.warningCircle, size: 15.sp, color: AppColors.error),
                        SizedBox(width: 6.w),
                        Expanded(child: Text(_error!, style: AppText.caption(color: AppColors.error))),
                        if (_stale)
                          GestureDetector(
                            onTap: _reloading ? null : _reload,
                            child: Padding(
                              padding: EdgeInsets.only(left: 8.w),
                              child: Text(_reloading ? 'Reloading…' : 'Reload',
                                  style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (_reloaded && _error == null) ...[
                    SizedBox(height: 8.h),
                    Text('Latest version loaded — Save applies your change to it.',
                        style: AppText.caption(color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
            child: Row(
              children: [
                Expanded(child: PrimaryButton(label: 'Cancel', ghost: true, onTap: () => Navigator.of(context).pop())),
                SizedBox(width: 10.w),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(label: _saving ? 'Saving…' : 'Save', onTap: _saving || _stale ? null : _save),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    switch (f.kind) {
      case InfoEditKind.boolean:
        return Wrap(spacing: 8.w, children: [
          for (final (v, l) in const [('true', 'Yes'), ('false', 'No')])
            ChoiceChip(label: Text(l), selected: _value == v, onSelected: (_) => setState(() => _value = v)),
        ]);
      case InfoEditKind.date:
        final current = DateTime.tryParse(_value);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: f.label,
              readOnly: true,
              value: current == null ? '' : sheetDateLabel(current),
              hint: 'Pick a date',
              suffixIcon: PhosphorIconsRegular.calendarBlank,
              errorText: _errorInField ? _error : null,
              onTap: () async {
                final d = await pickSheetDate(context, _value);
                if (d != null && mounted) setState(() => _value = sheetIsoDate(d));
              },
            ),
            if (_value.isNotEmpty)
              TextButton(onPressed: () => setState(() => _value = ''), child: const Text('Clear date')),
          ],
        );
      case InfoEditKind.select:
        return Column(
          children: [
            for (final (v, l) in f.options)
              InkWell(
                onTap: () => setState(() => _value = v),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 4.w),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(l,
                            style: AppText.custom(
                                size: 14,
                                weight: _value == v ? FontWeight.w700 : FontWeight.w500,
                                color: AppColors.textPrimary)),
                      ),
                      if (_value == v) Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.blueBright),
                    ],
                  ),
                ),
              ),
          ],
        );
      default:
        return AppTextField(
          label: f.label,
          controller: _ctrl,
          multiline: f.kind == InfoEditKind.multiline,
          hint: f.placeholder,
          errorText: _errorInField ? _error : null,
          keyboardType: switch (f.kind) {
            InfoEditKind.email => TextInputType.emailAddress,
            InfoEditKind.phone => TextInputType.phone,
            InfoEditKind.number => const TextInputType.numberWithOptions(decimal: true),
            InfoEditKind.multiline => TextInputType.multiline,
            _ => TextInputType.text,
          },
        );
    }
  }
}
