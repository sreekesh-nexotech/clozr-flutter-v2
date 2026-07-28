import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/followup.dart';
import '../../domain/repositories/followups_repository.dart';
import '../../infrastructure/data_sources/local/followups_mock_ds.dart';
import '../../infrastructure/repositories/followups_repository_impl.dart';

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final followupsRepositoryProvider = Provider<FollowupsRepository>(
  (ref) => const FollowupsRepositoryImpl(FollowupsMockDataSource()),
);

/// Async source of all follow-ups.
final followupsProvider = FutureProvider<List<Followup>>(
  (ref) => ref.watch(followupsRepositoryProvider).getFollowups(),
);

/// Look up a single follow-up by id (used by the detail screen).
final followupByIdProvider = Provider.family<Followup?, String>((ref, id) {
  final list = ref.watch(followupsProvider).valueOrNull;
  if (list == null) return null;
  for (final f in list) {
    if (f.id == id) return f;
  }
  return null;
});

// ── List UI state ──

/// Active status tab on the Follow-ups list.
final followupTabProvider = StateProvider<String>((ref) => 'all');

/// Search query on the Follow-ups list.
final followupSearchProvider = StateProvider<String>((ref) => '');

/// Whether the search field is expanded.
final followupSearchOpenProvider = StateProvider<bool>((ref) => false);

const _fuOrder = {'overdue': 0, 'due': 1, 'done': 2};

/// Follow-ups filtered by the active tab + search, sorted overdue→due→done.
final visibleFollowupsProvider = Provider<List<Followup>>((ref) {
  final all = ref.watch(followupsProvider).valueOrNull ?? const [];
  final tab = ref.watch(followupTabProvider);
  final q = ref.watch(followupSearchProvider).trim().toLowerCase();

  Iterable<Followup> out = all;
  if (tab != 'all') out = out.where((f) => f.status == tab);
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
