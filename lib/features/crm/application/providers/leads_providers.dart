import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/leads_repository.dart';
import '../../infrastructure/data_sources/local/leads_mock_ds.dart';
import '../../infrastructure/data_sources/remote/leads_remote_ds.dart';
import '../../infrastructure/repositories/leads_api_repository.dart';
import '../../infrastructure/repositories/leads_repository_impl.dart';
import '../filters/leads_filter_spec.dart';

/// DI seam: mock-backed by default; API-backed when a base URL is configured.
final leadsRepositoryProvider = Provider<LeadsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const LeadsRepositoryImpl(LeadsMockDataSource());
  }
  return LeadsApiRepository(
    LeadsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Async source of all leads.
final leadsProvider = FutureProvider<List<Lead>>(
  (ref) => ref.watch(leadsRepositoryProvider).getLeads(),
);

/// Look up a single lead by id (used by the detail screen).
final leadByIdProvider = Provider.family<Lead?, String>((ref, id) {
  final leads = ref.watch(leadsProvider).valueOrNull;
  if (leads == null) return null;
  for (final l in leads) {
    if (l.id == id) return l;
  }
  return null;
});

// ── List UI state ──

/// Active status tab on the Leads list.
final leadTabProvider = StateProvider<String>((ref) => 'all');

/// Search query on the Leads list.
final leadSearchProvider = StateProvider<String>((ref) => '');

/// Whether the search field is expanded.
final leadSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Whether to show all leads (true) or only mine (false, the default) —
/// the prototype's `teamAll` flag / "My leads" default view.
final leadTeamAllProvider = StateProvider<bool>((ref) => false);

/// The base list before the status tab is applied (respects the mine/all view).
final leadBaseProvider = Provider<List<Lead>>((ref) {
  final leads = ref.watch(leadsProvider).valueOrNull ?? const [];
  final all = ref.watch(leadTeamAllProvider);
  return all ? leads : leads.where((l) => l.isMine).toList();
});

/// Leads filtered by the active tab + search query + drawer filters.
final visibleLeadsProvider = Provider<List<Lead>>((ref) {
  final base = ref.watch(leadBaseProvider);
  final tab = ref.watch(leadTabProvider);
  final q = ref.watch(leadSearchProvider).trim().toLowerCase();
  final filters = ref.watch(leadFiltersProvider);

  Iterable<Lead> out = base;
  if (tab != 'all') out = out.where((l) => l.status == tab);
  if (!filters.isEmpty) out = out.where((l) => leadMatchesFilters(l, filters));
  if (q.isNotEmpty) {
    out = out.where((l) =>
        l.name.toLowerCase().contains(q) ||
        (l.company ?? '').toLowerCase().contains(q) ||
        l.project.toLowerCase().contains(q) ||
        l.id.toLowerCase().contains(q));
  }
  return out.toList();
});

/// Count of leads for a given tab key within [base].
int leadTabCount(List<Lead> base, String key) {
  if (key == 'all') return base.length;
  return base.where((l) => l.status == key).length;
}
