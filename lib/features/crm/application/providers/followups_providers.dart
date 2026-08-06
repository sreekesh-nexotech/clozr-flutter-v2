import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../filters/followup_filter_codec.dart';
import '../../../../data/api/user_directory.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../data/api/status_keys.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/view_schema.dart';
import '../../domain/repositories/followups_repository.dart';
import '../../infrastructure/data_sources/local/followups_mock_ds.dart';
import '../../infrastructure/data_sources/remote/followup_schema_remote_ds.dart';
import '../../infrastructure/data_sources/remote/followups_remote_ds.dart';
import '../../infrastructure/repositories/followups_api_repository.dart';
import '../../infrastructure/repositories/followups_repository_impl.dart';
import '../filters/followups_filter_spec.dart';
import 'crm_catalog_providers.dart';

/// DI seam: API-backed when a base URL is configured, mock seed otherwise.
final followupsRepositoryProvider = Provider<FollowupsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const FollowupsRepositoryImpl(FollowupsMockDataSource());
  }
  return FollowupsApiRepository(
    FollowupsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// One server-side follow-up query — the drawer's filters as `/crm/tasks/`
/// params. Value-equal by content so it can key a provider family: identical
/// queries share one request, and any edit is a different key, which is what
/// makes it refetch.
@immutable
class FollowupQuery {
  const FollowupQuery({this.filters = const {}});

  final Map<String, dynamic> filters;

  /// Order-independent identity.
  String get signature {
    final parts = [for (final e in filters.entries) '${e.key}=${e.value}']..sort();
    return parts.join('&');
  }

  @override
  bool operator ==(Object other) =>
      other is FollowupQuery && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

/// Follow-ups for one query.
final followupsScopedProvider =
    FutureProvider.family<List<Followup>, FollowupQuery>(
  (ref, q) => ref.watch(followupsRepositoryProvider).getFollowups(filters: q.filters),
);

/// The drawer's filters as server params.
///
/// Empty in mock mode: the seed source cannot execute query params, so there
/// [visibleFollowupsProvider] keeps matching locally instead.
Map<String, dynamic> followupFilterParamsFor(
    FilterValues values, FollowupFilterCodec codec) {
  if (!ApiConfig.apiEnabled || values.isEmpty) return const {};
  return codec.encode(values);
}

final followupFilterCodecProvider = Provider<FollowupFilterCodec>(
  (ref) => FollowupFilterCodec(
    statuses: ref.watch(taskStatusOptionsProvider),
    currentUserId: UserDirectory.currentUserId,
  ),
);

final followupFilterParamsProvider = Provider<Map<String, dynamic>>(
  (ref) => followupFilterParamsFor(
    ref.watch(followupFiltersProvider),
    ref.watch(followupFilterCodecProvider),
  ),
);

/// Async source of the follow-ups list, narrowed by the drawer server-side.
final followupsProvider = FutureProvider<List<Followup>>(
  (ref) => ref.watch(
    followupsScopedProvider(
      FollowupQuery(filters: ref.watch(followupFilterParamsProvider)),
    ).future,
  ),
);

/// Refetches the follow-ups list. **Use this after any write.**
///
/// Invalidating [followupsProvider] on its own does nothing: it is a thin
/// wrapper that awaits `followupsScopedProvider(query).future`, and that family
/// entry stays cached — the wrapper re-runs, reads the same already-completed
/// future, and no request is made. The scoped family is what has to be dropped,
/// which is easy to miss because the wrapper is the provider every screen
/// watches.
void refreshFollowups(WidgetRef ref) {
  ref.invalidate(followupsScopedProvider);
  ref.invalidate(followupsProvider);
}

/// The follow-ups linked to one lead — the Follow-ups tab on the lead detail
/// screen. Keyed by lead id: `GET /crm/tasks/?related_to=lead&
/// related_to_id=<lead_id>&is_followup=true`.
final leadFollowupsProvider =
    FutureProvider.family<List<Followup>, String>((ref, leadId) {
  if (leadId.isEmpty) return Future.value(const <Followup>[]);
  return ref.watch(followupsRepositoryProvider).getFollowupsForLead(leadId);
});

/// Look up a single follow-up by id (used by the detail screen). Reads the
/// merged "all" set so session drafts and status overrides are reflected.
final followupByIdProvider = Provider.family<Followup?, String>((ref, id) {
  final list = ref.watch(followupsAllProvider);
  for (final f in list) {
    if (f.id == id) return f;
  }
  return null;
});

// ── List UI state ──

/// Follow-ups added locally this session (from the Add follow-up sheet).
/// Prepended to the repo-backed list so new records appear immediately.
final followupDraftsProvider = StateProvider<List<Followup>>((ref) => const []);

/// Session-local status overrides for existing follow-ups, keyed by id → status.
/// Existing records come from a read-only [followupsProvider], so a status
/// change (e.g. → done) has nowhere else to persist; it is layered on here and
/// picked up by both the list and the detail via [followupsAllProvider].
/// A status change applied locally while its write is in flight.
///
/// Carries **both** halves because the screen groups by one and shows the
/// other: [key] is the folded bucket the tabs and the date logic use, [name] is
/// the org's own status ("In Progress") that the pill renders. Storing only the
/// bucket — as this used to — meant an optimistic change lost the org name and
/// the pill fell back to "Upcoming".
@immutable
class FollowupStatusOverride {
  const FollowupStatusOverride({required this.key, this.name = ''});

  /// `overdue` | `due` | `done`.
  final String key;

  /// The org's status name, empty in mock mode (which has no catalog).
  final String name;

  @override
  bool operator ==(Object other) =>
      other is FollowupStatusOverride && other.key == key && other.name == name;

  @override
  int get hashCode => Object.hash(key, name);
}

final followupStatusOverrideProvider =
    StateProvider<Map<String, FollowupStatusOverride>>((ref) => const {});

/// The full follow-up set: session-added drafts first, then the repo list, with
/// any session status overrides applied.
final followupsAllProvider = Provider<List<Followup>>((ref) {
  final repo = ref.watch(followupsProvider).valueOrNull ?? const [];
  final drafts = ref.watch(followupDraftsProvider);
  final overrides = ref.watch(followupStatusOverrideProvider);
  final merged = [...drafts, ...repo];
  if (overrides.isEmpty) return merged;
  return [
    for (final f in merged)
      _overrideApplies(overrides[f.id], f)
          ? _followupWithStatus(f, overrides[f.id]!)
          : f,
  ];
});

/// The org lane whose folded bucket is [bucket], by name.
///
/// An optimistic change knows which bucket it wants (`done`, `due`) but the
/// pill needs the org's word for it. Empty when no lane folds that way — mock
/// mode, or a catalog that has not loaded — which the override treats as "keep
/// whatever name the row already had".
String followupLaneNameFor(List<CatalogOption> lanes, String bucket) {
  for (final l in lanes) {
    final folded = crmTaskStatusKey(name: l.name, type: l.statusType);
    if (bucket == 'done' ? folded == 'done' : folded != 'done') return l.name;
  }
  return '';
}

/// Whether [o] would actually change [f] — no point rebuilding otherwise.
bool _overrideApplies(FollowupStatusOverride? o, Followup f) =>
    o != null && (o.key != f.status || (o.name.isNotEmpty && o.name != f.statusName));

/// [_followupWithStatus], exposed for tests — the rebuild is where an
/// optimistic change silently lost fields, so it is worth pinning directly.
@visibleForTesting
Followup followupWithStatusForTest(Followup f, FollowupStatusOverride o) =>
    _followupWithStatus(f, o);

/// Rebuilds a [Followup] with a new status (the entity has no `copyWith`).
///
/// [Followup.statusName] and [Followup.priority] move with it. Dropping them —
/// as this used to — meant an optimistically-changed follow-up lost the org's
/// status name (so its pill fell back to a built-in bucket and its tab misfiled
/// it) and lost its priority from the card.
Followup _followupWithStatus(Followup f, FollowupStatusOverride o) => Followup(
      id: f.id,
      kind: f.kind,
      contact: f.contact,
      custId: f.custId,
      leadId: f.leadId,
      company: f.company,
      due: f.due,
      time: f.time,
      status: o.key,
      statusName: o.name.isNotEmpty ? o.name : f.statusName,
      priority: f.priority,
      owner: f.owner,
      agenda: f.agenda,
    );

/// Active status tab on the Follow-ups list.
final followupTabProvider = StateProvider<String>((ref) => 'all');

/// Search query on the Follow-ups list.
final followupSearchProvider = StateProvider<String>((ref) => '');

/// Whether the search field is expanded.
final followupSearchOpenProvider = StateProvider<bool>((ref) => false);

const _fuOrder = {'overdue': 0, 'due': 1, 'done': 2};

/// Follow-ups filtered by the active tab + search + drawer filters, sorted
/// overdue→due→done.
final visibleFollowupsProvider = Provider<List<Followup>>((ref) {
  final all = ref.watch(followupsAllProvider);
  final tab = ref.watch(followupTabProvider);
  final q = ref.watch(followupSearchProvider).trim().toLowerCase();
  final filters = ref.watch(followupFiltersProvider);

  Iterable<Followup> out = all;
  if (tab != 'all' && ref.watch(followupTabsProvider).any((t) => t.id == tab)) {
    out = out.where((f) => f.statusKey == tab);
  }
  // The drawer already ran server-side in API mode, so `all` is the matching
  // set. Mock mode has no query engine, so it is matched here instead. The
  // "Related to" section stays local either way — a follow-up row carries no
  // company, and there is no param for the linked record's name.
  if (!ApiConfig.apiEnabled) {
    if (!filters.isEmpty) out = out.where((f) => followupMatchesFilters(f, filters));
  } else {
    final related = filters.choice('companies');
    if (related != null && related.isActive) {
      out = out.where((f) => FilterMatch.matchAnyOf(related, [f.company]));
    }
  }
  if (q.isNotEmpty) {
    out = out.where((f) =>
        f.company.toLowerCase().contains(q) ||
        f.contact.toLowerCase().contains(q) ||
        f.kind.toLowerCase().contains(q) ||
        f.agenda.toLowerCase().contains(q));
  }
  final list = out.toList()
    ..sort((a, b) => (_fuOrder[a.status] ?? 0) - (_fuOrder[b.status] ?? 0));
  return list;
});

/// Count of follow-ups for a given tab key.
int followupTabCount(List<Followup> all, String key) {
  if (key == 'all') return all.length;
  return all.where((f) => f.statusKey == key).length;
}

/// One status tab on the Follow-ups list.
class FollowupTab {
  const FollowupTab(this.id, this.label);

  /// The value the list filters by — matched against [Followup.statusKey].
  final String id;
  final String label;
}

/// The status tab row: the org's own task statuses.
///
/// Follow-ups are Tasks, so their statuses are the org's `CRMTaskStatus` set —
/// Open / In Progress / Completed / Cancelled on a default org. The built-in
/// Overdue / Upcoming / Done vocabulary could not express two of those, so a
/// cancelled follow-up read as Upcoming. **Overdue is not a status** — it is a
/// due-date condition, and lives on the drawer's Due date chips.
///
/// Falls back to the built-in buckets while the catalog is in flight, in mock
/// mode, and if the fetch failed, so the row always renders.
final followupTabsProvider = Provider<List<FollowupTab>>((ref) {
  final statuses = ref.watch(taskStatusOptionsProvider);
  return [
    const FollowupTab('all', 'All'),
    if (statuses.isNotEmpty)
      for (final s in statuses) FollowupTab(s.key, s.name)
    else ...[
      const FollowupTab('overdue', 'Overdue'),
      const FollowupTab('due', 'Upcoming'),
      const FollowupTab('done', 'Done'),
    ],
  ];
});

/// Null in mock mode, which is what makes the schema resolve empty there.
final followupSchemaRemoteDataSourceProvider =
    Provider<FollowupSchemaRemoteDataSource?>((ref) {
  if (!ApiConfig.apiEnabled) return null;
  return FollowupSchemaRemoteDataSource(ref.watch(apiServiceProvider));
});

/// `GET /crm/tasks/schema/?view_type=mobile&is_followup=true` — the org's own
/// card layout. Fetched once per org: it changes when an admin edits it, not
/// when follow-ups change.
final followupCardSchemaFutureProvider = FutureProvider<ViewSchema>((ref) async {
  final ds = ref.watch(followupSchemaRemoteDataSourceProvider);
  return ds == null ? ViewSchema.empty : ds.fetchCardSchema();
});

/// Synchronous view — empty while in flight, so the list renders immediately
/// with the built-in layout and adopts the org's one when it arrives rather
/// than holding the rows behind a spinner.
final followupCardSchemaProvider = Provider<ViewSchema>(
  (ref) =>
      ref.watch(followupCardSchemaFutureProvider).valueOrNull ?? ViewSchema.empty,
);

/// `GET /crm/tasks/schema/?view_type=detail&is_followup=true` — the org's own
/// Follow-up field set, which drives the Edit follow-up form.
///
/// Kept separate from the Task detail schema: the two are independently
/// configurable, and an org routinely shows fields on a follow-up that a task
/// does not have.
final followupDetailSchemaFutureProvider = FutureProvider<ViewSchema>((ref) async {
  final ds = ref.watch(followupSchemaRemoteDataSourceProvider);
  return ds == null ? ViewSchema.empty : ds.fetchDetailSchema();
});

/// Synchronous view of [followupDetailSchemaFutureProvider].
final followupDetailSchemaProvider = Provider<ViewSchema>(
  (ref) =>
      ref.watch(followupDetailSchemaFutureProvider).valueOrNull ?? ViewSchema.empty,
);
