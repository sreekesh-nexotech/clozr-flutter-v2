import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../widgets/app_bottom_sheet.dart';
import 'filter_models.dart';

/// Presents the spec-driven filter drawer as a Clozr bottom sheet and resolves
/// to the applied [FilterValues] on Apply, or `null` if dismissed.
///
/// * [spec] — the module's drawer configuration.
/// * [initial] — the currently-applied filters (seeds the editable draft).
/// * [previewCount] — live result count for the Apply button; called on every
///   draft change with the in-progress draft.
/// * [onSaveView] — when non-null, a Save-view affordance appears; the callback
///   receives the entered name and the current draft (fired while the sheet
///   stays open).
/// * [activeViewName] — name of the saved view currently applied, if any;
///   prefills the save field and relabels the action "Update".
/// * [existingViewNames] — every other saved view's name. Typing one of these
///   (that isn't [activeViewName]) asks for confirmation before saving, since
///   the save call updates a same-named view in place rather than rejecting it
///   — silent otherwise, so a typo could clobber someone else's view unseen.
Future<FilterValues?> showFilterSheet({
  required BuildContext context,
  required FilterSpec spec,
  required int Function(FilterValues draft) previewCount,
  FilterValues? initial,
  void Function(String name, FilterValues draft)? onSaveView,
  String? activeViewName,
  Set<String> existingViewNames = const {},
}) {
  return showClozrSheet<FilterValues>(
    context: context,
    builder: (_) => _FilterSheet(
      spec: spec,
      initial: initial,
      previewCount: previewCount,
      onSaveView: onSaveView,
      activeViewName: activeViewName,
      existingViewNames: existingViewNames,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.spec,
    required this.initial,
    required this.previewCount,
    required this.onSaveView,
    required this.activeViewName,
    required this.existingViewNames,
  });

  final FilterSpec spec;
  final FilterValues? initial;
  final int Function(FilterValues draft) previewCount;
  final void Function(String name, FilterValues draft)? onSaveView;
  final String? activeViewName;
  final Set<String> existingViewNames;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late FilterValues _draft;
  final _search = <String, String>{}; // fieldId -> query
  final _controllers = <String, TextEditingController>{};
  bool _savePanel = false;
  late final TextEditingController _viewName;

  // Which date field (if any) has its inline calendar open, and for which bound.
  String? _calFieldId;
  String? _calBound; // 'from' | 'to'
  DateTime _calMonth = kFilterToday;

  @override
  void initState() {
    super.initState();
    _draft = widget.spec.defaults();
    if (widget.initial != null) _draft.overlay(widget.initial!);
    _viewName = TextEditingController(text: widget.activeViewName ?? '');
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _viewName.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(String key, String initial) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: initial));

  void _set(String id, FilterValue v) => setState(() => _draft[id] = v);

  void _resetAll() {
    setState(() {
      _draft = widget.spec.defaults();
      _search.clear();
      _calFieldId = null;
      for (final c in _controllers.values) {
        c.text = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.previewCount(_draft);
    final active = _draft.activeCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(active),
        Flexible(
          child: SingleChildScrollView(
            // A search-and-select field can be anywhere in the drawer; once its
            // keyboard is up it covers the sections below and there is no other
            // way to put it away without leaving the field.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final section in widget.spec.sections) ...[
                  _sectionTitle(section.title),
                  for (final field in section.fields) _field(field),
                ],
              ],
            ),
          ),
        ),
        _footer(count),
      ],
    );
  }

  // ── Header ──
  Widget _header(int active) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18.w, 4.h, 14.w, 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.spec.title,
                    style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
                SizedBox(height: 1.h),
                Text(active > 0 ? '$active filter${active == 1 ? '' : 's'} set' : 'No filters set',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 32.w,
              height: 32.w,
              decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(9.r)),
              child: Icon(Icons.close_rounded, size: 17.sp, color: AppColors.textLabelAlt),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: EdgeInsets.only(top: 16.h, bottom: 4.h),
        child: Text(title.toUpperCase(),
            style: AppText.custom(
                size: 11.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.7)),
      );

  // ── Field dispatch ──
  Widget _field(FilterField f) {
    switch (f.control) {
      case FilterControl.checkboxGroup:
      case FilterControl.checkboxIsNot:
        return _checkboxField(f);
      case FilterControl.searchSelect:
        return _searchField(f);
      case FilterControl.radio:
        return _radioField(f);
      case FilterControl.dateRange:
        return _dateField(f);
      case FilterControl.numberRange:
        return _rangeField(f);
    }
  }

  BoxDecoration get _rowDivider =>
      BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgChipGrey)));

  // ── Checkbox group (+ optional is/is-not) ──
  Widget _checkboxField(FilterField f) {
    final v = _draft.choice(f.id) ?? ChoiceValue();
    return Container(
      padding: EdgeInsets.only(top: 12.h, bottom: 4.h),
      decoration: _rowDivider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(f.label, style: _fieldLabel)),
              if (f.isNotToggle) _isNotToggle(f, v),
            ],
          ),
          SizedBox(height: 2.h),
          if (f.twoCol)
            _twoColGrid(f, v)
          else
            for (final o in f.options) _checkRow(f, v, o),
        ],
      ),
    );
  }

  Widget _twoColGrid(FilterField f, ChoiceValue v) {
    final rows = <Widget>[];
    for (var i = 0; i < f.options.length; i += 2) {
      rows.add(Row(
        children: [
          Expanded(child: _checkRow(f, v, f.options[i])),
          SizedBox(width: 10.w),
          Expanded(
              child: i + 1 < f.options.length ? _checkRow(f, v, f.options[i + 1]) : const SizedBox()),
        ],
      ));
    }
    return Column(children: rows);
  }

  Widget _checkRow(FilterField f, ChoiceValue v, FilterOption o) {
    final on = v.ids.contains(o.id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _set(f.id, v.toggled(o.id)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 9.h, horizontal: 4.w),
        child: Row(
          children: [
            _checkBox(on),
            SizedBox(width: 9.w),
            if (o.icon != null) ...[
              Icon(o.icon, size: 15.sp, color: AppColors.textLabel),
              SizedBox(width: 6.w),
            ],
            if (o.dot != null) ...[
              Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: o.dot, shape: BoxShape.circle)),
              SizedBox(width: 7.w),
            ],
            Flexible(
              child: Text(o.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(
                      size: 13.5,
                      weight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? AppColors.textPrimary : AppColors.textLabel)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkBox(bool on) => Container(
        width: 20.w,
        height: 20.w,
        decoration: BoxDecoration(
          color: on ? AppColors.navy : AppColors.white,
          borderRadius: BorderRadius.circular(6.r),
          border: on ? null : Border.all(color: AppColors.borderInput, width: 1.5),
        ),
        child: on ? Icon(PhosphorIconsBold.check, size: 12.sp, color: AppColors.white) : null,
      );

  // ── Search & Select ──
  Widget _searchField(FilterField f) {
    final v = _draft.choice(f.id) ?? ChoiceValue();
    final q = (_search[f.id] ?? '').trim().toLowerCase();
    final opts = q.isEmpty
        ? f.options
        : f.options.where((o) => o.label.toLowerCase().contains(q)).toList();
    return Container(
      padding: EdgeInsets.only(top: 12.h, bottom: 10.h),
      decoration: _rowDivider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(f.label, style: _fieldLabel)),
              _isNotToggle(f, v),
            ],
          ),
          SizedBox(height: 8.h),
          _textInput(
            controller: _ctrl('${f.id}:q', ''),
            hint: f.placeholder ?? 'Search…',
            prefix: PhosphorIconsRegular.magnifyingGlass,
            onChanged: (t) => setState(() => _search[f.id] = t),
          ),
          SizedBox(height: 4.h),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 240.h),
            child: opts.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 4.w),
                    child: Text('No matches',
                        style: AppText.custom(
                            size: 12.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  )
                : SingleChildScrollView(
                    child: Column(children: [for (final o in opts) _checkRow(f, v, o)]),
                  ),
          ),
          if (v.ids.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Text('${v.ids.length} selected',
                  style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.blueBright)),
            ),
        ],
      ),
    );
  }

  // ── Radio ──
  Widget _radioField(FilterField f) {
    final v = _draft.radio(f.id) ?? RadioValue(id: f.radioDefaultId, defaultId: f.radioDefaultId);
    return Container(
      padding: EdgeInsets.only(top: 12.h, bottom: 4.h),
      decoration: _rowDivider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.label, style: _fieldLabel),
          SizedBox(height: 2.h),
          for (final o in f.options)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _set(f.id, v.select(o.id)),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 9.h, horizontal: 4.w),
                child: Row(
                  children: [
                    _radioDot(v.id == o.id),
                    SizedBox(width: 9.w),
                    Text(o.label,
                        style: AppText.custom(
                            size: 13.5,
                            weight: v.id == o.id ? FontWeight.w600 : FontWeight.w500,
                            color: v.id == o.id ? AppColors.textPrimary : AppColors.textLabel)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _radioDot(bool on) => Container(
        width: 19.w,
        height: 19.w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: on ? AppColors.navy : AppColors.borderInput, width: on ? 5.5 : 1.5),
        ),
      );

  // ── Date ──
  Widget _dateField(FilterField f) {
    final v = _draft.date(f.id) ?? const DateValue();
    return Container(
      padding: EdgeInsets.only(top: 12.h, bottom: 12.h),
      decoration: _rowDivider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.label, style: _fieldLabel),
          SizedBox(height: 9.h),
          Wrap(
            spacing: 7.w,
            runSpacing: 7.h,
            children: [
              for (final c in f.dateChips)
                _dateChip(kFilterChipLabels[c] ?? c, v.chip == c, () {
                  setState(() {
                    _draft[f.id] = v.withChip(c);
                    _calFieldId = null;
                  });
                }),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: _dateInput(f, v, 'from', v.from)),
              SizedBox(width: 9.w),
              Expanded(child: _dateInput(f, v, 'to', v.to)),
            ],
          ),
          if (_calFieldId == f.id) ...[
            SizedBox(height: 10.h),
            _calendar(f, v),
          ],
        ],
      ),
    );
  }

  Widget _dateInput(FilterField f, DateValue v, String bound, DateTime? value) {
    final open = _calFieldId == f.id && _calBound == bound;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bound == 'from' ? 'From' : 'To', style: _miniLabel),
        SizedBox(height: 5.h),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            if (open) {
              _calFieldId = null;
            } else {
              _calFieldId = f.id;
              _calBound = bound;
              _calMonth = value ?? kFilterToday;
            }
          }),
          child: Container(
            height: 42.h,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: open ? AppColors.navy : AppColors.borderInput),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(value != null ? _fmtDate(value) : 'Any',
                      style: AppText.custom(
                          size: 13.5,
                          weight: FontWeight.w500,
                          color: value != null ? AppColors.textBody : AppColors.textPlaceholder)),
                ),
                Icon(PhosphorIconsRegular.calendarBlank, size: 15.sp, color: AppColors.textPlaceholder),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _calendar(FilterField f, DateValue v) {
    final first = DateTime(_calMonth.year, _calMonth.month, 1);
    final daysInMonth = DateTime(_calMonth.year, _calMonth.month + 1, 0).day;
    final leading = first.weekday % 7; // Sun-first grid
    final selected = _calBound == 'from' ? v.from : v.to;
    return Container(
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.borderInput),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _calNav(PhosphorIconsBold.caretLeft,
                  () => setState(() => _calMonth = DateTime(_calMonth.year, _calMonth.month - 1, 1))),
              Text('${_monthName(_calMonth.month)} ${_calMonth.year}',
                  style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
              _calNav(PhosphorIconsBold.caretRight,
                  () => setState(() => _calMonth = DateTime(_calMonth.year, _calMonth.month + 1, 1))),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: AppText.custom(
                            size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
                  ),
                ),
            ],
          ),
          SizedBox(height: 4.h),
          for (var week = 0; week * 7 < leading + daysInMonth; week++)
            Row(
              children: [
                for (var wd = 0; wd < 7; wd++)
                  Expanded(child: _calCell(f, v, week * 7 + wd - leading + 1, daysInMonth, selected)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _calCell(FilterField f, DateValue v, int day, int daysInMonth, DateTime? selected) {
    if (day < 1 || day > daysInMonth) return SizedBox(height: 32.h);
    final date = DateTime(_calMonth.year, _calMonth.month, day);
    final on = selected != null &&
        selected.year == date.year &&
        selected.month == date.month &&
        selected.day == date.day;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _draft[f.id] = _calBound == 'from' ? v.withFrom(date) : v.withTo(date);
        _calFieldId = null;
      }),
      child: Container(
        height: 32.h,
        margin: EdgeInsets.all(1.5.w),
        decoration: BoxDecoration(
          color: on ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Center(
          child: Text('$day',
              style: AppText.custom(
                  size: 12.5,
                  weight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? AppColors.white : AppColors.textBody)),
        ),
      ),
    );
  }

  Widget _calNav(IconData icon, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 30.w,
          height: 30.w,
          decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(8.r)),
          child: Icon(icon, size: 13.sp, color: AppColors.textSecondary),
        ),
      );

  // ── Number range ──
  Widget _rangeField(FilterField f) {
    final v = _draft.range(f.id) ?? const RangeValue();
    return Container(
      padding: EdgeInsets.only(top: 12.h, bottom: 12.h),
      decoration: _rowDivider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(f.label, style: _fieldLabel),
              if (f.unit != null) ...[
                SizedBox(width: 7.w),
                Text(f.unit!,
                    style: AppText.custom(
                        size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ],
            ],
          ),
          SizedBox(height: 9.h),
          Row(
            children: [
              Expanded(child: _rangeBox(f, v, 'min')),
              SizedBox(width: 9.w),
              Expanded(child: _rangeBox(f, v, 'max')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rangeBox(FilterField f, RangeValue v, String bound) {
    final current = bound == 'min' ? v.min : v.max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bound == 'min' ? 'Min' : 'Max', style: _miniLabel),
        SizedBox(height: 5.h),
        _textInput(
          controller: _ctrl('${f.id}:$bound', current?.let(_fmtNum) ?? ''),
          hint: 'Any',
          number: true,
          onChanged: (t) {
            final parsed = double.tryParse(t.trim());
            _set(f.id, bound == 'min' ? v.withMin(parsed) : v.withMax(parsed));
          },
        ),
      ],
    );
  }

  // ── Footer ──
  Widget _footer(int count) {
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 24.h),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_savePanel && widget.onSaveView != null) ...[
            Row(
              children: [
                Expanded(
                  child: _textInput(
                    controller: _viewName,
                    hint: 'Name this view…',
                  ),
                ),
                SizedBox(width: 8.w),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final name = _viewName.text.trim();
                    if (name.isEmpty) return;
                    if (name != widget.activeViewName && widget.existingViewNames.contains(name)) {
                      final overwrite = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('View already exists'),
                          content: Text(
                            'A view named "$name" already exists. Saving will replace its filters.',
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: Text('Replace', style: TextStyle(color: AppColors.error)),
                            ),
                          ],
                        ),
                      );
                      if (overwrite != true || !mounted) return;
                    }
                    widget.onSaveView!(name, _draft.copy());
                    setState(() => _savePanel = false);
                  },
                  child: Container(
                    height: 44.h,
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.tintNavy, borderRadius: BorderRadius.circular(11.r)),
                    child: Text(widget.activeViewName != null ? 'Update' : 'Save',
                        style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.navy)),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
          ],
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _resetAll,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 6.h),
                  child: Text('Reset All',
                      style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
                ),
              ),
              SizedBox(width: 10.w),
              if (widget.onSaveView != null) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _savePanel = !_savePanel),
                  child: Container(
                    width: 48.w,
                    height: 48.h,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: _savePanel ? AppColors.navy : AppColors.borderInput),
                    ),
                    child: Icon(PhosphorIconsRegular.bookmarkSimple, size: 19.sp, color: AppColors.textSecondary),
                  ),
                ),
                SizedBox(width: 10.w),
              ],
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(_draft.copy()),
                  child: Container(
                    height: 48.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
                    child: Text('Apply · $count ${count == 1 ? 'result' : 'results'}',
                        style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Shared bits ──
  Widget _isNotToggle(FilterField f, ChoiceValue v) {
    return Container(
      padding: EdgeInsets.all(2.w),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(9.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg('is', !v.isNot, () => _set(f.id, v.withMode(false))),
          _seg('is not', v.isNot, () => _set(f.id, v.withMode(true))),
        ],
      ),
    );
  }

  Widget _seg(String label, bool on, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
          decoration: BoxDecoration(
            color: on ? AppColors.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(7.r),
          ),
          child: Text(label,
              style: AppText.custom(
                  size: 11.5, weight: FontWeight.w700, color: on ? AppColors.white : AppColors.textMuted2)),
        ),
      );

  Widget _dateChip(String label, bool on, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // No fixed height + no `alignment:` — inside a Wrap an aligned Container
        // expands to the full available width (Align fills bounded constraints),
        // which stacked the chips full-width. Sizing to the padded label instead
        // lets them wrap compactly like the prototype's date chips (#10).
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: on ? AppColors.navy : AppColors.white,
            borderRadius: BorderRadius.circular(9.r),
            border: on ? null : Border.all(color: AppColors.borderChip),
          ),
          child: Text(label,
              style: AppText.custom(
                  size: 12.5,
                  weight: on ? FontWeight.w700 : FontWeight.w600,
                  color: on ? AppColors.white : AppColors.textLabel)),
        ),
      );

  Widget _textInput({
    required TextEditingController controller,
    required String hint,
    IconData? prefix,
    bool number = false,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      height: 44.h,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(11.r),
        border: Border.all(color: AppColors.borderInput),
      ),
      child: Row(
        children: [
          if (prefix != null) ...[
            Icon(prefix, size: 15.sp, color: AppColors.textPlaceholder),
            SizedBox(width: 8.w),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
              inputFormatters:
                  number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
              style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textBody),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _fieldLabel =>
      AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textSecondary);
  TextStyle get _miniLabel =>
      AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textPlaceholder);

  String _fmtDate(DateTime d) => '${d.day} ${_monthName(d.month)} ${d.year}';
  String _fmtNum(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  String _monthName(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
