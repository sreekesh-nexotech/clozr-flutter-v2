import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/followup.dart';
import '../providers/crm_catalog_providers.dart';
import '../providers/followups_providers.dart';
import 'tasks_filter_spec.dart' show parseCrmDate;

/// Follow-ups filter — spec-driven drawer (audit §4). Wired exactly like the
/// Leads reference. Sections: Type & status · People & company · Due date.

/// The built-in type vocabulary, used only when the org's catalog has not
/// loaded (mock mode, or a failed fetch).
///
/// It is a **fallback, not the source of truth**: follow-up types are org-
/// editable and rows join on the type *name* exactly, so a hard-coded list
/// silently matches nothing the moment an org renames or adds one.
const List<String> kBuiltinFollowupTypes = [
  'Call', 'Email', 'Meeting', 'WhatsApp', 'Site visit', 'Payment',
];

/// The records the loaded follow-ups hang off, sorted and de-duplicated.
///
/// Derived from the follow-ups themselves, not from lead/customer companies:
/// a follow-up row carries no company, and `Followup.company` is really
/// `related_to.label` — the linked lead or customer's own **name**. Offering
/// company names against name values produced a filter that matched nothing.
List<String> _relatedRecords(List<Followup> fus) {
  final seen = <String>{};
  for (final f in fus) {
    if (f.company.isNotEmpty) seen.add(f.company);
  }
  final list = seen.toList()..sort();
  return list;
}

/// Build the Follow-ups drawer spec (audit §4).
FilterSpec buildFollowupsFilterSpec({
  required List<Followup> followups,
  List<AppUser> roster = MockUsers.reps,
  List<CatalogOption> typeCatalog = const [],
  List<CatalogOption> statusCatalog = const [],
  List<CatalogOption> priorityCatalog = const [],
}) {
  final users = [
    for (final u in roster) FilterOption(id: u.id, label: u.name),
  ];
  final companies = _relatedRecords(followups)
      .map((c) => FilterOption(id: c, label: c))
      .toList();
  // The org's own types when the catalog has loaded, otherwise the built-in
  // vocabulary. Both the option id and its label are the type **name**, which
  // is what a follow-up row carries and what the matcher compares.
  final typeNames = typeCatalog.isNotEmpty
      ? [for (final t in typeCatalog) t.name]
      : kBuiltinFollowupTypes;
  final types = [
    for (final t in typeNames) FilterOption(id: t, label: t),
  ];
  // The org's own task statuses. The built-in trio is a fallback only: it
  // cannot express "In Progress" or "Cancelled", which real orgs use.
  final statuses = statusCatalog.isNotEmpty
      ? [for (final st in statusCatalog) FilterOption(id: st.key, label: st.name)]
      : const [
          FilterOption(id: 'due', label: 'Upcoming'),
          FilterOption(id: 'overdue', label: 'Overdue'),
          FilterOption(id: 'done', label: 'Done'),
        ];

  // Priorities are offered under the org's **own** spelling, unmatched.
  //
  // Deliberately unlike the Tasks drawer, which folds them to the built-in
  // Urgent/High/Medium/Low display vocabulary: `CrmTask.priority` is folded on
  // the way in, but `Followup.priority` keeps the raw name the API sent. Folding
  // here would offer "High" against rows carrying "high" and match nothing.
  final priorities = [
    for (final p in priorityCatalog)
      FilterOption(
        id: p.name,
        label: p.name,
        dot: StatusMeta$.priorityTone[priorityKey(p.name)]?.fg,
      ),
  ];

  return FilterSpec(
    title: 'Follow-ups',
    sections: [
      // Type and status carry the is / is not toggle, like the Leads drawer's
      // Source / Product / Stage. The matcher already honoured `isNot` on every
      // field here — these two simply never offered the control, so "everything
      // except Email" could not be expressed.
      FilterSection(title: 'Type & status', fields: [
        FilterField(
            id: 'types',
            label: 'Type',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: types),
        FilterField(
            id: 'statuses',
            label: 'Status',
            control: FilterControl.checkboxIsNot,
            isNotToggle: true,
            twoCol: true,
            options: statuses),
      ]),
      // Omitted entirely when the catalog has not loaded: an empty checkbox
      // group is a section that cannot do anything, and there is no built-in
      // priority vocabulary a follow-up row would match.
      if (priorities.isNotEmpty)
        FilterSection(title: 'Priority', fields: [
          FilterField(
              id: 'priorities',
              label: 'Priority',
              control: FilterControl.checkboxIsNot,
              isNotToggle: true,
              options: priorities),
        ]),
      FilterSection(title: 'People & company', fields: [
        FilterField(
            id: 'owners',
            label: 'Assigned to',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search user…',
            options: users),
        // Labelled for what the value actually is. A follow-up row carries no
        // company: this is `related_to.label`, the linked lead or customer's
        // own name, so calling it "Company" named the wrong thing.
        FilterField(
            id: 'companies',
            label: 'Related to',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search lead or customer…',
            options: companies),
      ]),
      FilterSection(title: 'Due date', fields: [
        const FilterField(
            id: 'due',
            label: 'Due date',
            control: FilterControl.dateRange,
            dateChips: ['overdue', 'today', 'tomorrow', 'next7', 'next30', 'next60', 'next90']),
      ]),
    ],
  );
}

/// Evaluate a follow-up against applied filter values.
bool followupMatchesFilters(Followup f, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('types'), [f.kind])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('statuses'), [f.statusKey])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('priorities'), [f.priority])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('owners'), [f.owner])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('companies'), [f.company])) return false;
  if (!FilterMatch.matchDate(v.date('due'), parseCrmDate(f.due))) return false;
  return true;
}

// ── Providers ──

/// The Follow-ups drawer spec, derived from the company universe.
final followupsFilterSpecProvider = Provider<FilterSpec>((ref) {
  return buildFollowupsFilterSpec(
    followups: ref.watch(followupsAllProvider),
    roster: ref.watch(rosterProvider),
    typeCatalog: ref.watch(followupTypeOptionsProvider),
    statusCatalog: ref.watch(taskStatusOptionsProvider),
    priorityCatalog: ref.watch(taskPriorityOptionsProvider),
  );
});

/// Applied drawer filters for the Follow-ups list (the source of the badge).
final followupFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Follow-ups list (bookmark chips).
final followupSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
