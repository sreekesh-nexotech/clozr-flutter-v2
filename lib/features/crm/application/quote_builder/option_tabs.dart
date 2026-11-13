import 'quote_builder_draft.dart';
import 'quote_lines.dart';

/// Alternative options in the quote builder (rulebook v1.7) — a port of the
/// webapp's `builder/optionTabs.ts`. On an `options` template a quote is a group
/// of up to three options that share everything (party, payment, validity,
/// template fields …) except their lines and title. The builder edits ONE option
/// at a time: the active option's lines and title live in the draft (so the line
/// editor, the live GST preview and validation work unchanged); the others wait
/// in their tab. Pure, no Flutter.
const optionTabLabels = ['A', 'B', 'C'];

String optionLabel(int index) =>
    index < optionTabLabels.length ? optionTabLabels[index] : '${index + 1}';

int _tabSeq = 0;
String _nextTabKey() => 'option-${++_tabSeq}';

class OptionTab {
  const OptionTab({
    required this.key,
    this.quotationId = '',
    this.title = '',
    required this.items,
    this.linesDirty = false,
  });

  final String key;

  /// Edit: the option's quote ('' for an option added in this session).
  final String quotationId;
  final String title;
  final List<QuoteFormItem> items;

  /// Edit: this option's lines were changed (else its saved lines are kept).
  final bool linesDirty;

  OptionTab withActive(
          String title, List<QuoteFormItem> items, bool linesDirty) =>
      OptionTab(
          key: key,
          quotationId: quotationId,
          title: title,
          items: items,
          linesDirty: linesDirty);
}

/// What the active option holds in the draft.
typedef ActiveOption = ({
  String title,
  List<QuoteFormItem> items,
  bool linesDirty
});

/// The tabs with the active option's draft written back into its tab.
List<OptionTab> stashActive(
        List<OptionTab> tabs, int active, ActiveOption draft) =>
    [
      for (var i = 0; i < tabs.length; i++)
        i == active
            ? tabs[i].withActive(draft.title, draft.items, draft.linesDirty)
            : tabs[i],
    ];

/// A new quote's first tab (the draft's current lines).
OptionTab firstTab(ActiveOption draft) => OptionTab(
    key: _nextTabKey(),
    title: draft.title,
    items: draft.items,
    linesDirty: draft.linesDirty);

/// "Add alternative": a copy of the active option's lines (re-keyed), so the rep
/// only swaps what differs. Never beyond [max] options.
List<OptionTab> addAlternative(
    List<OptionTab> tabs, int active, ActiveOption draft, int max) {
  final stashed = stashActive(tabs, active, draft);
  if (stashed.length >= max) return stashed;
  return [
    ...stashed,
    OptionTab(
        key: _nextTabKey(),
        items: [for (final it in draft.items) it.cloned()],
        linesDirty: true),
  ];
}

/// Remove an option (never the last one). Returns the tabs and the index to show next.
({List<OptionTab> tabs, int active}) removeOption(
    List<OptionTab> tabs, int active, ActiveOption draft, int index) {
  final stashed = stashActive(tabs, active, draft);
  if (stashed.length <= 1) return (tabs: stashed, active: active);
  final next = [
    for (var i = 0; i < stashed.length; i++)
      if (i != index) stashed[i]
  ];
  final shown = index == active
      ? (index - 1 < 0 ? 0 : index - 1)
      : (active > index ? active - 1 : active);
  return (
    tabs: next,
    active: shown > next.length - 1 ? next.length - 1 : shown
  );
}

/// The index the primary star moves to after removing [removed]. Removing the
/// primary hands it to the first option.
int primaryAfterRemove(int primary, int removed) {
  if (removed == primary) return 0;
  return removed < primary ? primary - 1 : primary;
}

/// Tabs for editing a saved group (one per option, A → C).
List<OptionTab> tabsFromOptions(List<SavedQuote> options) => [
      for (final o in options)
        OptionTab(
            key: _nextTabKey(),
            quotationId: o.id,
            title: o.title,
            items: itemsFromSavedLines(o.lines)),
    ];

/// Per-option problems the save must block on (the active option is validated by
/// the builder itself). `problem` is `empty` or `line`.
List<({String label, String problem})> optionProblems(
    List<OptionTab> tabs, bool isEdit) {
  final out = <({String label, String problem})>[];
  for (var i = 0; i < tabs.length; i++) {
    final t = tabs[i];
    final label = optionLabel(i);
    if (t.items.any((it) => lineProblem(it) != null)) {
      out.add((label: label, problem: 'line'));
    } else if (includedLines(t.items).isEmpty &&
        (!isEdit || t.linesDirty || t.quotationId.isEmpty)) {
      out.add((label: label, problem: 'empty'));
    }
  }
  return out;
}

/// The block-reason footer for the first problem option ("Option B: add at least one line item.").
String? optionBlockReason(List<({String label, String problem})> problems) =>
    problems.isEmpty
        ? null
        : 'Option ${problems.first.label}: ${problems.first.problem == 'empty' ? 'add at least one line item' : 'fix its line items'}.';

/// The options of a group write. An edit keeps an untouched option's saved lines.
List<Map<String, dynamic>> toOptionInputs(List<OptionTab> tabs, bool isEdit) =>
    [
      for (final t in tabs)
        {
          if (t.quotationId.isNotEmpty) 'quotation_id': t.quotationId,
          'quotation_title': t.title,
          if (!(isEdit && t.quotationId.isNotEmpty && !t.linesDirty))
            'line_items': toLineRows(t.items),
        },
    ];

/// Whether a group edit changes the option set or any option (beyond the shared fields).
bool optionsChanged(List<OptionTab> tabs, List<SavedQuote> saved) {
  if (tabs.length != saved.length) return true;
  for (var i = 0; i < tabs.length; i++) {
    if (tabs[i].quotationId != saved[i].id ||
        tabs[i].linesDirty ||
        tabs[i].title != saved[i].title) return true;
  }
  return false;
}

/// `POST /quotations/option-groups/`: the shared quote fields once + `options` +
/// `primary_index`. [shared] is the single-quote create body — its option-level
/// keys (lines, title) travel per option instead.
Map<String, dynamic> toNewGroupJson(
        Map<String, dynamic> shared, List<OptionTab> tabs, int primaryIndex) =>
    {
      ...(Map<String, dynamic>.from(shared)
        ..remove('line_items')
        ..remove('quotation_title')),
      'options': toOptionInputs(tabs, false),
      'primary_index': primaryIndex,
    };

/// `PATCH /quotations/option-groups/{id}/`: only the changed shared fields, plus
/// `options` / `primary_quotation_id` when they changed. The group's template is
/// fixed and a status moves only through the group actions.
Map<String, dynamic> toGroupPatchJson(
  Map<String, dynamic> sharedPatch,
  List<OptionTab> tabs, {
  required bool optionsDiffer,
  String? primaryQuotationId,
}) =>
    {
      ...(Map<String, dynamic>.from(sharedPatch)
        ..remove('line_items')
        ..remove('quotation_title')
        ..remove('template')
        ..remove('status_id')),
      if (optionsDiffer) 'options': toOptionInputs(tabs, true),
      if (primaryQuotationId != null && primaryQuotationId.isNotEmpty)
        'primary_quotation_id': primaryQuotationId,
    };
