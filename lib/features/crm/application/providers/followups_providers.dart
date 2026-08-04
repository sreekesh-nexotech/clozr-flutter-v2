import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/followup.dart';
import '../../domain/repositories/followups_repository.dart';
import '../../infrastructure/data_sources/local/followups_mock_ds.dart';
import '../../infrastructure/repositories/followups_repository_impl.dart';
import '../filters/followups_filter_spec.dart';

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final followupsRepositoryProvider = Provider<FollowupsRepository>(
  (ref) => const FollowupsRepositoryImpl(FollowupsMockDataSource()),
);

/// Async source of all follow-ups.
final followupsProvider = FutureProvider<List<Followup>>(
  (ref) => ref.watch(followupsRepositoryProvider).getFollowups(),
);

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
final followupStatusOverrideProvider =
    StateProvider<Map<String, String>>((ref) => const {});

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
      (overrides[f.id] != null && overrides[f.id] != f.status)
          ? _followupWithStatus(f, overrides[f.id]!)
          : f,
  ];
});

/// Rebuilds a [Followup] with a new status (the entity has no `copyWith`).
Followup _followupWithStatus(Followup f, String status) => Followup(
      id: f.id,
      kind: f.kind,
      contact: f.contact,
      custId: f.custId,
      leadId: f.leadId,
      company: f.company,
      due: f.due,
      time: f.time,
      status: status,
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
  if (tab != 'all') out = out.where((f) => f.status == tab);
  if (!filters.isEmpty) out = out.where((f) => followupMatchesFilters(f, filters));
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
  return all.where((f) => f.status == key).length;
}
