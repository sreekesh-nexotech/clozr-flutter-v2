import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/mock_users.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/followup.dart';
import '../providers/crm_catalog_providers.dart';
import '../providers/leads_providers.dart';
import '../providers/saved_filters_providers.dart';
import 'tasks_filter_spec.dart';

/// Follow-ups filter — the webapp's task drawer (`TasksListScreen` with
/// `isFollowup`): Assignee, Status, Task type, Priority, Team and Due date,
/// sent as the same `/crm/tasks/` params, so a saved view means the same thing
/// on both lists.

/// The built-in type vocabulary, used only when the org's catalog has not
/// loaded (mock mode, or a failed fetch).
///
/// It is a **fallback, not the source of truth**: follow-up types are org-
/// editable and rows join on the type *name* exactly, so a hard-coded list
/// silently matches nothing the moment an org renames or adds one.
const List<String> kBuiltinFollowupTypes = [
  'Call', 'Email', 'Meeting', 'WhatsApp', 'Site visit', 'Payment',
];

/// Build the Follow-ups drawer spec.
///
/// The type options are the org's **follow-up** types, keyed by name — the
/// value a row's `task_type` carries and `task_type__in` filters on. Users and
/// teams are the server's `module=followup` pickers, as on the webapp.
FilterSpec buildFollowupsFilterSpec({
  List<AppUser> roster = MockUsers.reps,
  List<CatalogOption> typeCatalog = const [],
  List<CatalogOption> priorityCatalog = const [],
  List<CatalogOption> statusCatalog = const [],
  List<CatalogOption> teamCatalog = const [],
  List<CatalogOption> assignableUsers = const [],
}) =>
    buildTasksFilterSpec(
      title: 'Filter follow-ups by:',
      roster: roster,
      typeCatalog: [for (final t in typeCatalog) CatalogOption(id: t.name, name: t.name)],
      builtinTypes: kBuiltinFollowupTypes,
      priorityCatalog: priorityCatalog,
      statusCatalog: statusCatalog,
      teamCatalog: teamCatalog,
      assignableUsers: assignableUsers,
    );

/// Evaluate a follow-up against applied filter values — mock mode only; the
/// API runs the drawer server-side.
bool followupMatchesFilters(Followup f, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('assignees'), [f.owner])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('types'), [f.kind])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('priorities'), [priorityKey(f.priority)])) return false;
  if (!FilterMatch.matchDate(v.date('due'), parseCrmDate(f.due))) return false;
  return true;
}

// ── Providers ──

/// The Follow-ups drawer spec, with the org's own vocabularies.
final followupsFilterSpecProvider = Provider<FilterSpec>(
  (ref) => buildFollowupsFilterSpec(
    roster: ref.watch(rosterProvider),
    typeCatalog: ref.watch(followupTypeOptionsProvider),
    priorityCatalog: ref.watch(taskPriorityOptionsProvider),
    statusCatalog: ref.watch(taskStatusOptionsProvider),
    teamCatalog: ref.watch(assignableTeamsForModuleProvider('followup')).valueOrNull ?? const [],
    assignableUsers: ref.watch(assignableUsersForModuleProvider('followup')).valueOrNull ?? const [],
  ),
);

/// The drawer as `/crm/tasks/` params — the Tasks codec, since the params and
/// a saved view's `filter_definition` are the same on both lists.
final followupFilterCodecProvider = Provider<TaskFilterCodec>((ref) => TaskFilterCodec(
      statuses: ref.watch(taskStatusOptionsProvider),
      priorities: ref.watch(taskPriorityOptionsProvider),
    ));

/// Applied drawer filters for the Follow-ups list (the source of the badge).
final followupFiltersProvider = StateProvider<FilterValues>((ref) {
  // A new sign-in rebuilds the API service; the next user starts unfiltered.
  ref.watch(apiServiceProvider);
  return FilterValues();
});

/// Saved views on the Follow-ups list — `/crm/saved-filters/?module=task`,
/// the **same** set the Tasks list shows (webapp: follow-ups have no module
/// of their own). Its own controller so applying a view here does not apply
/// it on Tasks.
final followupSavedFiltersProvider = StateNotifierProvider<SavedFiltersController, SavedFiltersState>(
  (ref) => SavedFiltersController(module: 'task', remote: ref.watch(savedFiltersRemoteProvider)),
);
