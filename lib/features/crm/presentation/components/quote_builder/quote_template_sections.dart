import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/network/app_error.dart';
import '../../../application/quote_builder/quote_template_parts.dart';
import 'qb_kit.dart';
import 'quote_totals_block.dart' show qbSheetButton;

/// The template-driven sections of the builder: the template's own fields,
/// the Item Quote layout's section headings, the "Quote details" popup and the
/// Terms & conditions clause list — each a port of its web component.

// ── Template fields ──────────────────────────────────────────────────────────

class TemplateFieldsSection extends StatefulWidget {
  const TemplateFieldsSection({
    super.key,
    required this.fields,
    required this.valueOf,
    required this.onChange,
    this.warnings = const [],
    this.loading = false,
    this.error,
    this.showMissing = false,
    this.disabled = false,
  });

  final List<TemplateField> fields;
  final Object Function(TemplateField) valueOf;
  final void Function(String key, Object value) onChange;
  final List<String> warnings;
  final bool loading;
  final String? error;

  /// Show "Required by this template." under blank required fields.
  final bool showMissing;
  final bool disabled;

  @override
  State<TemplateFieldsSection> createState() => _TemplateFieldsSectionState();
}

class _TemplateFieldsSectionState extends State<TemplateFieldsSection> {
  final _ctrls = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        QbSectionLabel('Template fields'),
        QbHint('Loading…'),
      ]);
    }
    if (widget.error != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const QbSectionLabel('Template fields'),
        QbHint(widget.error!, error: true),
      ]);
    }
    if (widget.fields.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const QbSectionLabel('Template fields · printed by the selected template'),
        for (final f in widget.fields) ...[
          _field(f),
          SizedBox(height: 12.h),
        ],
        if (widget.warnings.isNotEmpty)
          QbNotice(
            tone: QbTone.warning,
            icon: PhosphorIconsRegular.warning,
            children: [for (final w in widget.warnings) qbNoticeText(w)],
          ),
      ],
    );
  }

  Widget _field(TemplateField f) {
    final value = widget.valueOf(f);
    final missing = widget.showMissing && isFieldMissing(f, value);
    if (f.type == TemplateFieldType.boolean) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.disabled ? null : () => widget.onChange(f.key, value != true),
        child: Row(children: [
          Icon(value == true ? PhosphorIconsFill.checkSquare : PhosphorIconsRegular.square,
              size: 20.sp, color: value == true ? AppColors.navy : AppColors.textPlaceholder),
          SizedBox(width: 8.w),
          Expanded(child: QbFieldLabel(f.label, required: f.required)),
        ]),
      );
    }
    Widget input;
    if (f.type == TemplateFieldType.select) {
      input = QbPickerBox(
        text: value.toString(),
        placeholder: 'Select…',
        error: missing,
        onTap: widget.disabled
            ? null
            : () async {
                final v = await qbPickOne(context,
                    title: f.label, options: [('', 'Select…'), for (final o in f.options) (o, o)], selected: value.toString());
                if (v != null) widget.onChange(f.key, v);
              },
      );
    } else if (f.type == TemplateFieldType.date) {
      input = QbPickerBox(
        text: value.toString(),
        placeholder: 'Pick a date',
        error: missing,
        icon: PhosphorIconsRegular.calendarBlank,
        onTap: widget.disabled
            ? null
            : () async {
                final init = DateTime.tryParse(value.toString()) ?? DateTime.now();
                final d = await showDatePicker(
                    context: context, initialDate: init, firstDate: DateTime(init.year - 5), lastDate: DateTime(init.year + 10));
                if (d != null) {
                  widget.onChange(f.key,
                      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
                }
              },
      );
    } else {
      final c = _ctrls.putIfAbsent(f.key, () => TextEditingController());
      qbSync(c, value.toString());
      input = f.type == TemplateFieldType.textarea
          ? Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: widget.disabled ? AppColors.bgChipGrey : AppColors.white,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: missing ? AppColors.error : AppColors.borderInput, width: 1.5),
              ),
              child: TextField(
                controller: c,
                enabled: !widget.disabled,
                minLines: 3,
                maxLines: 6,
                onChanged: (v) => widget.onChange(f.key, v),
                style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
              ),
            )
          : QbBox(
              controller: c,
              enabled: !widget.disabled,
              numeric: f.type == TemplateFieldType.number,
              error: missing,
              onChanged: (v) => widget.onChange(f.key, v),
            );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QbFieldLabel(f.label, required: f.required),
      SizedBox(height: 7.h),
      input,
      if (missing) const QbHint('Required by this template.', error: true),
    ]);
  }
}

// ── Section headings (Item Quote layout) ─────────────────────────────────────

class QuoteSectionsEditor extends StatelessWidget {
  const QuoteSectionsEditor({
    super.key,
    required this.headings,
    required this.picks,
    required this.onPicksChange,
    this.loading = false,
    this.error,
    this.showMissing = false,
    this.disabled = false,
  });

  final List<SectionHeading> headings;
  final List<SectionPick> picks;
  final ValueChanged<List<SectionPick>> onPicksChange;
  final bool loading;
  final String? error;
  final bool showMissing;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        QbSectionLabel('Quote sections'),
        QbHint('Loading sections…'),
      ]);
    }
    if (error != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const QbSectionLabel('Quote sections'),
        QbHint(error!, error: true),
      ]);
    }
    if (headings.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const QbSectionLabel('Quote sections · printed under the items, one heading each'),
        for (final h in headings) ...[
          _heading(context, h),
          SizedBox(height: 12.h),
        ],
      ],
    );
  }

  Widget _heading(BuildContext context, SectionHeading h) {
    final value = pickFor(picks, h.id);
    final missing = showMissing && h.isMandatory && value.isEmpty;
    String title(String id) {
      for (final o in h.options) {
        if (o.id == id) return '${o.title}${o.isDefault ? ' (default)' : ''}';
      }
      return '';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Flexible(child: QbFieldLabel(h.label)),
        if (h.isMandatory) ...[
          SizedBox(width: 6.w),
          Tooltip(
            message: 'Mandatory heading — the quote can’t be sent without an option here',
            child: Icon(PhosphorIconsFill.lock, size: 12.sp, color: AppColors.error),
          ),
        ],
      ]),
      SizedBox(height: 7.h),
      QbPickerBox(
        text: title(value),
        placeholder: h.isMandatory ? 'Choose an option…' : 'Not printed',
        error: missing,
        onTap: disabled
            ? null
            : () async {
                final v = await qbPickOne(context,
                    title: h.label,
                    options: [
                      ('', h.isMandatory ? 'Choose an option…' : 'Not printed'),
                      for (final o in h.options) (o.id, '${o.title}${o.isDefault ? ' (default)' : ''}'),
                    ],
                    selected: value);
                if (v != null) onPicksChange(withPick(picks, h.id, v));
              },
      ),
      if (missing) const QbHint('Required before the quote can be sent.', error: true),
    ]);
  }
}

// ── "Quote details" (spot inputs) ────────────────────────────────────────────

/// The "Quote details" popup: the fields typed when quoting plus record
/// columns that are empty for this party. Returns the typed values (blank
/// ones left out), or null on Cancel.
Future<Map<String, String>?> showSpotInputsSheet(
  BuildContext context, {
  required Future<List<SpotInputField>> fields,
  required Map<String, String> values,
  required String confirmLabel,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _SpotInputsSheet(fields: fields, values: values, confirmLabel: confirmLabel),
  );
}

class _SpotInputsSheet extends StatefulWidget {
  const _SpotInputsSheet({required this.fields, required this.values, required this.confirmLabel});
  final Future<List<SpotInputField>> fields;
  final Map<String, String> values;
  final String confirmLabel;

  @override
  State<_SpotInputsSheet> createState() => _SpotInputsSheetState();
}

class _SpotInputsSheetState extends State<_SpotInputsSheet> {
  final _ctrls = <String, TextEditingController>{};
  bool _attempted = false;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(SpotInputField f) =>
      _ctrls.putIfAbsent(f.key, () => TextEditingController(text: widget.values[f.key] ?? f.spotValue));

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88 - keyboard),
        decoration:
            BoxDecoration(color: AppColors.bgApp, borderRadius: BorderRadius.vertical(top: Radius.circular(24.r))),
        padding: EdgeInsets.fromLTRB(18.w, 18.h, 18.w, 22.h),
        child: FutureBuilder<List<SpotInputField>>(
          future: widget.fields,
          builder: (context, snap) {
            final ask = fieldsNeedingInput(snap.data ?? const []);
            final filled = [for (final f in snap.data ?? const <SpotInputField>[]) if (!f.needsInput && f.modelValue.isNotEmpty) f];
            final current = {for (final f in ask) f.key: _c(f).text};
            final missing = missingRequiredSpot(ask, current);
            final loading = snap.connectionState != ConnectionState.done;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Quote details', style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
                SizedBox(height: 10.h),
                Flexible(
                  child: loading
                      ? Padding(
                          padding: EdgeInsets.symmetric(vertical: 20.h),
                          child: Text('Looking up the record details…',
                              textAlign: TextAlign.center,
                              style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                        )
                      : snap.hasError
                          ? QbHint(snap.error is AppError ? (snap.error as AppError).bareMessage : 'Could not load the quote details.', error: true)
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                const QbHint(
                                    'These details are printed on the quote. Fields your records already fill are shown for reference; the rest are typed here (and used as the fallback when a record field is empty).'),
                                SizedBox(height: 12.h),
                                for (final f in ask) ...[
                                  QbFieldLabel(f.label, required: f.required),
                                  SizedBox(height: 6.h),
                                  _box(f, missing.any((m) => m.key == f.key) && _attempted),
                                  if (f.boxHint.isNotEmpty) QbHint(f.boxHint),
                                  SizedBox(height: 12.h),
                                ],
                                if (ask.isEmpty) const QbHint('Nothing to type — every field is filled from your records.'),
                                if (filled.isNotEmpty) ...[
                                  SizedBox(height: 6.h),
                                  Row(children: [
                                    Icon(PhosphorIconsRegular.database, size: 13.sp, color: AppColors.textLabelAlt),
                                    SizedBox(width: 6.w),
                                    const QbFieldLabel('Filled from your records'),
                                  ]),
                                  SizedBox(height: 8.h),
                                  for (final f in filled)
                                    Padding(
                                      padding: EdgeInsets.only(bottom: 8.h),
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(f.label,
                                            style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textMuted)),
                                        Text(f.modelValue,
                                            style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBody)),
                                      ]),
                                    ),
                                ],
                              ],
                            ),
                ),
                if (_attempted && missing.isNotEmpty)
                  QbHint('Fill in ${missing.map((f) => f.label).join(', ')}.', error: true),
                SizedBox(height: 14.h),
                Row(children: [
                  Expanded(child: qbSheetButton('Cancel', primary: false, onTap: () => Navigator.of(context).pop())),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: qbSheetButton(widget.confirmLabel,
                        primary: true,
                        onTap: loading
                            ? null
                            : () {
                                setState(() => _attempted = true);
                                if (missing.isNotEmpty) return;
                                Navigator.of(context).pop({
                                  for (final f in ask)
                                    if (_c(f).text.trim().isNotEmpty) f.key: _c(f).text.trim(),
                                });
                              }),
                  ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _box(SpotInputField f, bool error) {
    final c = _c(f);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: f.multiline ? 8.h : 0),
      constraints: BoxConstraints(minHeight: 44.h),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(11.r),
        border: Border.all(color: error ? AppColors.error : AppColors.borderInput, width: 1.5),
      ),
      child: TextField(
        controller: c,
        minLines: f.multiline ? 2 : 1,
        maxLines: f.multiline ? 4 : 1,
        onChanged: (_) => setState(() {}),
        style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody),
        decoration: const InputDecoration(isDense: true, border: InputBorder.none),
      ),
    );
  }
}

// ── Terms & conditions (clauses) ─────────────────────────────────────────────

class QuoteClausesEditor extends StatefulWidget {
  const QuoteClausesEditor({
    super.key,
    required this.rows,
    required this.onRowsChange,
    required this.library,
    required this.today,
    required this.legacy,
    required this.terms,
    required this.onTermsChange,
    this.libraryLoading = false,
    this.libraryError,
    this.termsDisabled = false,
    this.disabled = false,
  });

  final List<ClauseRow> rows;
  final ValueChanged<List<ClauseRow>> onRowsChange;
  final List<LibraryClause> library;
  final String today;

  /// Legacy mode: no clause rows — the free-text T&C box.
  final bool legacy;
  final String terms;
  final ValueChanged<String> onTermsChange;
  final bool libraryLoading;
  final String? libraryError;
  final bool termsDisabled;
  final bool disabled;

  @override
  State<QuoteClausesEditor> createState() => _QuoteClausesEditorState();
}

class _QuoteClausesEditorState extends State<QuoteClausesEditor> {
  final _expanded = <String>{};
  final _terms = TextEditingController();

  @override
  void dispose() {
    _terms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final addable = addableClauses(widget.library, widget.rows, widget.today);
    final showTermsBox = widget.legacy && !widget.termsDisabled;
    final rows = widget.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QbSectionLabel('Terms & conditions',
            trailing: widget.disabled
                ? null
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.libraryLoading || addable.isEmpty
                        ? null
                        : () async {
                            final id = await qbPickOne(context, title: 'Add a clause…', options: [
                              for (final c in addable) (c.id, '${c.title}${c.isMandatory ? ' (mandatory)' : ''}'),
                            ]);
                            if (id == null) return;
                            widget.onRowsChange(addLibraryClause(rows, addable.firstWhere((c) => c.id == id)));
                          },
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(PhosphorIconsBold.plus,
                          size: 12.sp,
                          color: addable.isEmpty ? AppColors.textPlaceholder : AppColors.blueBright),
                      SizedBox(width: 4.w),
                      Text(
                          widget.libraryLoading
                              ? 'Loading clauses…'
                              : addable.isEmpty
                                  ? 'No more clauses to add'
                                  : 'Add a clause…',
                          style: AppText.custom(
                              size: 12,
                              weight: FontWeight.w700,
                              color: addable.isEmpty ? AppColors.textPlaceholder : AppColors.blueBright)),
                    ]),
                  )),
        if (widget.libraryError != null) QbHint(widget.libraryError!, error: true),
        if (rows.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(13.r),
              border: Border.all(color: const Color(0xFFE6E7EA)),
            ),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) _row(rows, i),
            ]),
          ),
        if (rows.isEmpty && !showTermsBox)
          QbHint(widget.termsDisabled
              ? 'This quote’s terms are not included in your workspace’s quote fields.'
              : 'No clauses on this quote yet.'),
        if (rows.isNotEmpty && !widget.legacy)
          const QbHint('Mandatory clauses are marked with a lock and stay on the quote. The order here is the order printed.'),
        if (showTermsBox) ...[
          Builder(builder: (_) {
            qbSync(_terms, widget.terms);
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: widget.disabled ? AppColors.bgChipGrey : AppColors.white,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: AppColors.borderInput, width: 1.5),
              ),
              child: TextField(
                controller: _terms,
                enabled: !widget.disabled,
                minLines: 3,
                maxLines: 8,
                onChanged: widget.onTermsChange,
                style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'T&C printed on the quote..',
                  hintStyle: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
                ),
              ),
            );
          }),
          if (rows.isNotEmpty && widget.terms.trim().isNotEmpty)
            const QbHint('This text is kept as the last clause once the quote is saved with clauses.'),
        ],
      ],
    );
  }

  Widget _row(List<ClauseRow> rows, int i) {
    final row = rows[i];
    final text = clauseText(row.bodyHtml);
    final open = _expanded.contains(row.key);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        border: i == 0 ? null : const Border(top: BorderSide(color: Color(0xFFF3F4F5))),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 20.w,
          child: Text('${i + 1}.', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textMuted)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(row.title.isEmpty ? 'Untitled clause' : row.title,
                    style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              if (row.isMandatory) ...[
                SizedBox(width: 6.w),
                Tooltip(
                  message: 'Mandatory clause — it can’t be removed from the quote',
                  child: Icon(PhosphorIconsFill.lock, size: 12.sp, color: AppColors.textMuted),
                ),
              ],
            ]),
            if (text.isNotEmpty) ...[
              SizedBox(height: 3.h),
              Text(text,
                  maxLines: open ? null : 2,
                  overflow: open ? null : TextOverflow.ellipsis,
                  style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textSecondary)),
            ],
            if (text.length > 140)
              GestureDetector(
                onTap: () => setState(() => open ? _expanded.remove(row.key) : _expanded.add(row.key)),
                child: Padding(
                  padding: EdgeInsets.only(top: 3.h),
                  child: Text(open ? 'Show less' : 'Show more',
                      style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.blueBright)),
                ),
              ),
          ]),
        ),
        if (!widget.disabled) ...[
          SizedBox(width: 6.w),
          QbIconButton(
            icon: PhosphorIconsRegular.arrowUp,
            size: 28.w,
            onTap: i == 0 ? null : () => widget.onRowsChange(moveClause(rows, row.key, -1)),
          ),
          SizedBox(width: 3.w),
          QbIconButton(
            icon: PhosphorIconsRegular.arrowDown,
            size: 28.w,
            onTap: i == rows.length - 1 ? null : () => widget.onRowsChange(moveClause(rows, row.key, 1)),
          ),
          SizedBox(width: 3.w),
          canRemoveClause(row)
              ? QbIconButton(
                  icon: PhosphorIconsRegular.trash,
                  size: 28.w,
                  danger: true,
                  onTap: () => widget.onRowsChange(removeClause(rows, row.key)),
                )
              : QbIconButton(
                  icon: PhosphorIconsRegular.lockSimple,
                  size: 28.w,
                  tooltip: 'Mandatory clause — it can’t be removed',
                ),
        ],
      ]),
    );
  }
}
