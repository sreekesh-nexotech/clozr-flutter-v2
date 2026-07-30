/// Spec-driven filter engine — feature-agnostic model layer.
///
/// A module describes its drawer once as a [FilterSpec] (sections → fields),
/// the generic filter sheet renders it, and the module's list uses the pure
/// [FilterMatch] helpers to evaluate the applied [FilterValues] against each
/// row. Ported 1:1 from the web prototype's unified filter (`_fspec` /
/// `fMatch`), so semantics match the audit exactly.
library;

import 'package:flutter/widgets.dart';

/// The seven control patterns from the audit (§1). Every drawer filter in the
/// app is one of these.
enum FilterControl {
  /// Flat checkbox list, 1–2 columns. Operator: is any of (OR within).
  checkboxGroup,

  /// Checkbox list with an is / is-not segmented toggle above it.
  checkboxIsNot,

  /// Searchable, internally-scrolling checkbox list for large datasets. Always
  /// carries the is / is-not toggle.
  searchSelect,

  /// Single choice, always defaults to its first option (All / Any).
  radio,

  /// Quick-range chips + From/To month calendar (mutually exclusive).
  dateRange,

  /// Min / Max numeric inputs; either bound may be empty.
  numberRange,
}

/// One selectable value within a control (a checkbox row, radio row, or
/// search-select row). [icon] and [dot] are optional adornments used by the
/// icon/dot checkbox variants (e.g. task types, priorities, statuses).
class FilterOption {
  const FilterOption({required this.id, required this.label, this.icon, this.dot});

  final String id;
  final String label;
  final IconData? icon;
  final Color? dot;
}

/// A single configured filter (one row in a module's audit table).
class FilterField {
  const FilterField({
    required this.id,
    required this.label,
    required this.control,
    this.options = const [],
    this.dateChips = const [],
    this.unit,
    this.unitScale = 1,
    this.searchable = false,
    this.isNotToggle = false,
    this.placeholder,
    this.twoCol = false,
  });

  final String id;
  final String label;
  final FilterControl control;

  /// Options for checkbox / radio / search-select controls.
  final List<FilterOption> options;

  /// Canonical quick-range chip keys this date field exposes (subset of
  /// [kFilterChipLabels]). Empty for non-date controls.
  final List<String> dateChips;

  /// Unit label shown beside a number range (e.g. `₹ lakhs`, `₹`).
  final String? unit;

  /// Multiplier applied to the user's number-range input before comparing to
  /// the raw row value (₹ lakhs → 100000; Products unit price → 1).
  final double unitScale;

  /// Whether a search box sits above the list (search-select only).
  final bool searchable;

  /// Whether the is / is-not segmented toggle is shown.
  final bool isNotToggle;

  /// Placeholder for the search box (search-select only).
  final String? placeholder;

  /// Two-column checkbox layout.
  final bool twoCol;

  /// The default option id for a radio (its first option). Radios are the only
  /// control with a non-empty default.
  String get radioDefaultId => options.isEmpty ? '' : options.first.id;

  /// The blank/default value for this field (matches the prototype `fBlank`).
  FilterValue blankValue() {
    switch (control) {
      case FilterControl.radio:
        return RadioValue(id: radioDefaultId, defaultId: radioDefaultId);
      case FilterControl.dateRange:
        return DateValue();
      case FilterControl.numberRange:
        return RangeValue();
      case FilterControl.checkboxGroup:
      case FilterControl.checkboxIsNot:
      case FilterControl.searchSelect:
        return ChoiceValue();
    }
  }
}

/// A titled group of fields inside the drawer body.
class FilterSection {
  const FilterSection({required this.title, required this.fields});
  final String title;
  final List<FilterField> fields;
}

/// A complete drawer configuration for one list.
class FilterSpec {
  const FilterSpec({required this.title, required this.sections});

  final String title;
  final List<FilterSection> sections;

  /// Flattened field list, in drawer order (mirrors `spec.all`).
  List<FilterField> get fields => [for (final s in sections) ...s.fields];

  FilterField? fieldById(String id) {
    for (final f in fields) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// A fresh [FilterValues] with every field at its blank/default value
  /// (mirrors `fDefaults`). Use as the drawer's starting draft and as the
  /// target of Reset All.
  FilterValues defaults() {
    final m = <String, FilterValue>{};
    for (final f in fields) {
      m[f.id] = f.blankValue();
    }
    return FilterValues(m);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Typed value holders
// ─────────────────────────────────────────────────────────────────────────

/// Base type for a single field's current value. [isActive] means the field
/// imposes a real constraint (an empty/default field is inactive).
abstract class FilterValue {
  const FilterValue();

  bool get isActive;
  FilterValue copy();
}

/// Value for checkbox / checkbox-is-not / search-select controls.
class ChoiceValue extends FilterValue {
  ChoiceValue({Set<String>? ids, this.isNot = false}) : ids = ids ?? <String>{};

  /// Selected option ids (OR within the group).
  final Set<String> ids;

  /// When true the operator is "is not any of".
  final bool isNot;

  @override
  bool get isActive => ids.isNotEmpty;

  @override
  ChoiceValue copy() => ChoiceValue(ids: {...ids}, isNot: isNot);

  ChoiceValue toggled(String id) {
    final next = {...ids};
    if (!next.remove(id)) next.add(id);
    return ChoiceValue(ids: next, isNot: isNot);
  }

  ChoiceValue withMode(bool notMode) => ChoiceValue(ids: {...ids}, isNot: notMode);

  @override
  bool operator ==(Object other) =>
      other is ChoiceValue &&
      other.isNot == isNot &&
      other.ids.length == ids.length &&
      other.ids.containsAll(ids);

  @override
  int get hashCode => Object.hash(isNot, Object.hashAllUnordered(ids));
}

/// Value for a radio control. Carries its [defaultId] so [isActive] can tell
/// whether the user moved off the default (All / Any).
class RadioValue extends FilterValue {
  const RadioValue({required this.id, required this.defaultId});

  final String id;
  final String defaultId;

  @override
  bool get isActive => id != defaultId;

  @override
  RadioValue copy() => RadioValue(id: id, defaultId: defaultId);

  RadioValue select(String next) => RadioValue(id: next, defaultId: defaultId);

  @override
  bool operator ==(Object other) =>
      other is RadioValue && other.id == id && other.defaultId == defaultId;

  @override
  int get hashCode => Object.hash(id, defaultId);
}

/// Value for a date control. A [chip] and a custom [from]/[to] range are
/// mutually exclusive (selecting one clears the other).
class DateValue extends FilterValue {
  const DateValue({this.chip, this.from, this.to});

  /// A canonical quick-range chip key (see [kFilterChipLabels]).
  final String? chip;
  final DateTime? from;
  final DateTime? to;

  @override
  bool get isActive => chip != null || from != null || to != null;

  @override
  DateValue copy() => DateValue(chip: chip, from: from, to: to);

  /// Select (or, if already selected, clear) a quick chip. Clears from/to.
  DateValue withChip(String? c) => DateValue(chip: chip == c ? null : c);

  /// Set the custom From bound; clears any chip.
  DateValue withFrom(DateTime? d) => DateValue(from: d, to: to);

  /// Set the custom To bound; clears any chip.
  DateValue withTo(DateTime? d) => DateValue(from: from, to: d);

  @override
  bool operator ==(Object other) =>
      other is DateValue && other.chip == chip && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(chip, from, to);
}

/// Value for a number-range control. [min]/[max] are in the field's display
/// unit (e.g. lakhs); scaling to the raw row value happens in [FilterMatch].
class RangeValue extends FilterValue {
  const RangeValue({this.min, this.max});

  final double? min;
  final double? max;

  @override
  bool get isActive => min != null || max != null;

  @override
  RangeValue copy() => RangeValue(min: min, max: max);

  RangeValue withMin(double? v) => RangeValue(min: v, max: max);
  RangeValue withMax(double? v) => RangeValue(min: min, max: v);

  @override
  bool operator ==(Object other) => other is RangeValue && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// A mutable fieldId → value map — the draft the drawer edits and the applied
/// state a list matches against.
class FilterValues {
  FilterValues([Map<String, FilterValue>? values]) : _m = values ?? <String, FilterValue>{};

  final Map<String, FilterValue> _m;

  FilterValue? operator [](String id) => _m[id];
  void operator []=(String id, FilterValue value) => _m[id] = value;

  Iterable<MapEntry<String, FilterValue>> get entries => _m.entries;

  // Typed accessors — return null when the field is absent or the wrong type.
  ChoiceValue? choice(String id) => _m[id] is ChoiceValue ? _m[id] as ChoiceValue : null;
  RadioValue? radio(String id) => _m[id] is RadioValue ? _m[id] as RadioValue : null;
  DateValue? date(String id) => _m[id] is DateValue ? _m[id] as DateValue : null;
  RangeValue? range(String id) => _m[id] is RangeValue ? _m[id] as RangeValue : null;

  /// Deep copy — the drawer mutates a copy so dismiss leaves state untouched.
  FilterValues copy() =>
      FilterValues({for (final e in _m.entries) e.key: e.value.copy()});

  /// Overlay another set's entries onto this one (used to seed a draft from an
  /// applied/saved state on top of spec defaults).
  void overlay(FilterValues other) {
    for (final e in other._m.entries) {
      _m[e.key] = e.value.copy();
    }
  }

  void clearAll() => _m.clear();

  /// True when no field imposes a constraint.
  bool get isEmpty => !_m.values.any((v) => v.isActive);

  /// Number of fields with a non-empty constraint — the badge count.
  int get activeCount => _m.values.where((v) => v.isActive).length;

  @override
  bool operator ==(Object other) {
    if (other is! FilterValues) return false;
    final a = _activeMap, b = other._activeMap;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Map<String, FilterValue> get _activeMap =>
      {for (final e in _m.entries) if (e.value.isActive) e.key: e.value};

  @override
  int get hashCode {
    var h = 0;
    for (final e in _activeMap.entries) {
      h ^= Object.hash(e.key, e.value);
    }
    return h;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Deterministic "today" + canonical quick-range chips
// ─────────────────────────────────────────────────────────────────────────

/// The prototype's fixed clock (`FTODAY = '2026-07-09'`). Used everywhere a
/// relative date range is computed so filter results are deterministic. Never
/// call [DateTime.now] in filter code.
final DateTime kFilterToday = DateTime(2026, 7, 9);

/// Canonical quick-range chip labels (the audit's full set). A field exposes
/// only the subset listed in [FilterField.dateChips].
const Map<String, String> kFilterChipLabels = {
  'overdue': 'Overdue',
  'today': 'Today',
  'tomorrow': 'Tomorrow',
  'yesterday': 'Yesterday',
  'month': 'This month',
  'next7': 'Next 7 days',
  'next30': 'Next 30 days',
  'next60': 'Next 60 days',
  'next90': 'Next 90 days',
  'last7': 'Last 7 days',
  'last30': 'Last 30 days',
  'last60': 'Last 60 days',
  'last90': 'Last 90 days',
};

// ─────────────────────────────────────────────────────────────────────────
// Pure matcher helpers (mirror `fMatch` / `fChipRange` / `inRange`)
// ─────────────────────────────────────────────────────────────────────────

/// Stateless matching helpers the module lists call, one per multi-valued
/// control type. Radio thresholds are module-specific, so a module evaluates
/// those itself against [RadioValue.id].
class FilterMatch {
  const FilterMatch._();

  /// OR within a checkbox / search-select group; respects the is-not toggle.
  /// An empty (inactive) value passes everything.
  static bool matchAnyOf(ChoiceValue? value, Iterable<String> itemValues) {
    if (value == null || value.ids.isEmpty) return true;
    final hit = itemValues.any(value.ids.contains);
    return value.isNot ? !hit : hit;
  }

  /// ≥ Min · ≤ Max · Between. [scale] converts the display-unit bounds to the
  /// row's raw unit (e.g. 100000 for ₹ lakhs). Inactive value passes.
  static bool matchRange(RangeValue? value, num? itemValue, {double scale = 1}) {
    if (value == null || !value.isActive) return true;
    final n = itemValue ?? 0;
    if (value.min != null && n < value.min! * scale) return false;
    if (value.max != null && n > value.max! * scale) return false;
    return true;
  }

  /// Quick chip OR custom From/To; ranges inclusive of both ends. Inactive
  /// value passes; a null [itemDate] fails an active constraint.
  static bool matchDate(DateValue? value, DateTime? itemDate) {
    if (value == null || !value.isActive) return true;
    if (itemDate == null) return false;
    final (from, to) = value.chip != null
        ? chipRange(value.chip!)
        : (value.from, value.to);
    final d = DateTime(itemDate.year, itemDate.month, itemDate.day);
    if (from != null && d.isBefore(_dayStart(from))) return false;
    if (to != null && d.isAfter(_dayStart(to))) return false;
    return true;
  }

  /// Resolve a canonical chip key to a `(from, to)` range against
  /// [kFilterToday]. Overdue = strictly before today (no start bound).
  static (DateTime? from, DateTime? to) chipRange(String chip) {
    final t = kFilterToday;
    switch (chip) {
      case 'overdue':
        return (null, _addDays(t, -1));
      case 'today':
        return (t, t);
      case 'tomorrow':
        return (_addDays(t, 1), _addDays(t, 1));
      case 'yesterday':
        return (_addDays(t, -1), _addDays(t, -1));
      case 'month':
        return (DateTime(t.year, t.month, 1), DateTime(t.year, t.month + 1, 0));
    }
    final m = RegExp(r'^(next|last)(\d+)$').firstMatch(chip);
    if (m == null) return (null, null);
    final n = int.parse(m.group(2)!);
    return m.group(1) == 'next' ? (t, _addDays(t, n)) : (_addDays(t, -n), t);
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
}
