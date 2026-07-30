# Spec-driven filter engine (`lib/core/filters/`)

A feature-agnostic filter drawer + matcher, built once and configured per list.
Ported 1:1 from the web prototype's unified filter (`_fspec` / `fMatch`) and the
`FILTER_AUDIT_spec.txt` control catalogue. **Leads is the reference wiring** —
copy its shape for every other list.

## Files

| File | What it provides |
| --- | --- |
| `filter_models.dart` | The reusable types: `FilterControl`, `FilterOption`, `FilterField`, `FilterSection`, `FilterSpec`, the typed value holders (`ChoiceValue`, `RadioValue`, `DateValue`, `RangeValue`), the `FilterValues` bag, and the pure `FilterMatch` helpers + deterministic `kFilterToday`. |
| `filter_sheet.dart` | `showFilterSheet(...)` — renders any spec as a Clozr bottom sheet, draft-then-apply, sticky footer (Reset All · Save view · Apply · N results). |
| `saved_view.dart` | `SavedView`, `SavedViewsState`, `SavedViewsController` (StateNotifier) — one per list key. |

## The seven controls (`FilterControl`)

`checkboxGroup` · `checkboxIsNot` · `searchSelect` · `radio` · `dateRange` ·
`numberRange`. (The seventh audit pattern, the status-chip tabs, lives on the
list header, not in the drawer.) Configure via `FilterField`:

- `twoCol` — two-column checkbox layout.
- `isNotToggle` — show the `is` / `is not` segmented toggle (mandatory on every
  `searchSelect`; opt-in on checkboxes).
- `searchable` + `placeholder` — search box above a `searchSelect` list
  (bounded to 240.h, internal scroll, "No matches" empty state).
- `options` — `FilterOption(id, label, icon?, dot?)` for checkbox/radio/search.
- `dateChips` — canonical chip keys (subset of `kFilterChipLabels`).
- `unit` + `unitScale` — number-range label and multiplier (₹ lakhs → `100000`;
  Products unit price → `1`).

Radios always default to their first option (All / Any); every other control
defaults to empty.

## Public API

```dart
// filter_models.dart
FilterSpec(title: String, sections: List<FilterSection>)
  List<FilterField> get fields;           // flattened, drawer order
  FilterField? fieldById(String id);
  FilterValues defaults();                // fresh draft, all fields blank/default

FilterValues([Map<String, FilterValue>? values])
  FilterValue? operator [](String id);
  void operator []=(String id, FilterValue v);
  ChoiceValue? choice(String id);  RadioValue? radio(String id);
  DateValue?   date(String id);    RangeValue? range(String id);
  FilterValues copy();
  void overlay(FilterValues other);
  void clearAll();
  bool get isEmpty;                       // no active constraint
  int  get activeCount;                   // the badge count
  // value-based == / hashCode (compares active fields only)

// Pure, static, deterministic (uses kFilterToday, never DateTime.now):
FilterMatch.matchAnyOf(ChoiceValue?, Iterable<String> itemValues) -> bool
FilterMatch.matchRange(RangeValue?, num? itemValue, {double scale = 1}) -> bool
FilterMatch.matchDate(DateValue?, DateTime? itemDate) -> bool
FilterMatch.chipRange(String chip) -> (DateTime? from, DateTime? to)

// filter_sheet.dart
Future<FilterValues?> showFilterSheet({
  required BuildContext context,
  required FilterSpec spec,
  required int Function(FilterValues draft) previewCount, // live Apply count
  FilterValues? initial,                                  // seeds editable draft
  void Function(String name, FilterValues draft)? onSaveView, // shows Save affordance
  String? activeViewName,                                 // relabels Save -> Update
});
// Resolves to the applied FilterValues on Apply, or null on dismiss.

// saved_view.dart
SavedView(id, name, values)
SavedViewsState(views: List<SavedView>, activeId: String?)  .active
SavedViewsController extends StateNotifier<SavedViewsState>
  SavedView upsert(String name, FilterValues values); // add or replace same-name; marks active
  void apply(String id);        // mark active
  void deactivate();            // clear active marker (view kept)
  void remove(String id);
  void clearActive();
```

## Wiring a new list (the Leads recipe)

See `lib/features/crm/application/filters/leads_filter_spec.dart` and
`.../presentation/screens/leads_screen.dart` for the full working example.

1. **Spec** — under the feature (`application/filters/<list>_filter_spec.dart`),
   build a `FilterSpec` from your data/settings. Provide it:
   ```dart
   final xFilterSpecProvider = Provider<FilterSpec>((ref) =>
       buildXFilterSpec(ref.watch(xListProvider).valueOrNull ?? const []));
   ```
2. **Applied-filters provider** — `final xFiltersProvider =
   StateProvider<FilterValues>((ref) => FilterValues());`
3. **Matcher** — one `bool xMatchesFilters(Item, FilterValues)` using the
   `FilterMatch` helpers for choice/range/date; evaluate radio thresholds
   yourself against `radio(id)?.id`. Apply it in your `visibleXProvider`:
   ```dart
   if (!filters.isEmpty) out = out.where((i) => xMatchesFilters(i, filters));
   ```
4. **Header button** — pass `filterCount: ref.watch(xFiltersProvider).activeCount`
   and `onFilter: _openFilters` to `ScreenTitleRow`. In `_openFilters`, call
   `showFilterSheet(...)` with `previewCount:
   (d) => base.where((i) => xMatchesFilters(i, d)).length`; on a non-null result
   set `xFiltersProvider` and `deactivate()` any active saved view.
5. **Saved views** — one
   `StateNotifierProvider<SavedViewsController, SavedViewsState>` per list. In
   `showFilterSheet`, `onSaveView: (name, draft) => controller.upsert(name, draft)`
   and `activeViewName: state.active?.name`. Render the chips with
   `SavedChipRow` (`presentation/components/saved_chip_row.dart`); its
   `showClearAlways: filterCount > 0` keeps the **Clear filters** chip reachable
   whenever *any* filter is active. Applying a view loads `view.values.copy()`
   into `xFiltersProvider` so the drawer reopens with those attributes editable.
6. **Badge** — already handled by step 4 (`activeCount`).
7. **Contextual add** — from the screen `build`, register the `+` action:
   ```dart
   registerAdd(ref, AddAction(label: 'Add x', run: (ctx) => ctx.push(Routes.addX)));
   ```

## Notes / invariants

- **Determinism** — all relative dates resolve against `kFilterToday`
  (2026-07-09). Never call `DateTime.now()` in filter code.
- **Unit scaling** — pass `scale: field.unitScale` to `matchRange`
  (₹ lakhs = 100000; Products unit price = 1).
- **Combination logic** — AND across fields, OR (or NOT-OR) within one
  multi-select. Empty field = inactive.
- **Draft-then-apply** — the sheet edits a private copy; nothing changes until
  Apply. Dismiss returns `null`.
- **Overdue** — strictly before today (no start bound); all other ranges are
  inclusive of both ends.
