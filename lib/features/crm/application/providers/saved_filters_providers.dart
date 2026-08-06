import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../data/api/user_directory.dart';
import '../../domain/entities/saved_filter.dart';
import '../../infrastructure/data_sources/remote/saved_filters_remote_ds.dart';
import '../filters/lead_filter_codec.dart';
import 'crm_catalog_providers.dart';

/// Saved-filter chips for one module.
class SavedFiltersState {
  const SavedFiltersState({
    this.filters = const [],
    this.activeId,
    this.loading = false,
    this.error,
  });

  final List<SavedFilter> filters;
  final String? activeId;

  /// True during the initial load only; writes refresh in place.
  final bool loading;

  /// Last load failure, for a non-blocking notice. Write failures are returned
  /// to the caller instead, so they can be shown against the action.
  final String? error;

  SavedFilter? get active {
    for (final f in filters) {
      if (f.id == activeId) return f;
    }
    return null;
  }

  SavedFiltersState copyWith({
    List<SavedFilter>? filters,
    String? activeId,
    bool clearActive = false,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      SavedFiltersState(
        filters: filters ?? this.filters,
        activeId: clearActive ? null : (activeId ?? this.activeId),
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Drives the saved-view chips against `/crm/saved-filters/`.
///
/// With no backend ([remote] null) it keeps the presets in memory for the
/// session, exactly as the prototype did — mock builds keep working without a
/// server, they just do not persist.
class SavedFiltersController extends StateNotifier<SavedFiltersState> {
  SavedFiltersController({required this.module, SavedFiltersRemoteDataSource? remote})
      : _remote = remote,
        super(const SavedFiltersState()) {
    if (_remote != null) load();
  }

  final String module;
  final SavedFiltersRemoteDataSource? _remote;

  var _seq = 0;

  Future<void> load() async {
    final remote = _remote;
    if (remote == null) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final filters = await remote.fetch(module);
      state = state.copyWith(filters: filters, loading: false);
    } on Object catch (e) {
      // The list behind the chips is fine; only the chips are missing.
      state = state.copyWith(loading: false, error: _message(e));
    }
  }

  /// Create, or update the same-named preset in place. Returns null on success
  /// and a user-safe message on failure (duplicate name, per-module limit,
  /// unknown filter key — all surfaced verbatim from the API).
  ///
  /// The saved preset becomes the active chip, matching the prototype.
  Future<String?> save(String name, Map<String, dynamic> definition) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Give the view a name.';
    if (definition.isEmpty) return 'Add at least one filter before saving.';

    final existing = _byName(trimmed);
    final remote = _remote;

    if (remote == null) {
      final saved = SavedFilter(
        id: existing?.id ?? 'view_${_seq++}',
        name: trimmed,
        definition: definition,
      );
      final list = [...state.filters];
      final at = list.indexWhere((f) => f.id == saved.id);
      at >= 0 ? list[at] = saved : list.add(saved);
      state = state.copyWith(filters: list, activeId: saved.id);
      return null;
    }

    try {
      final saved = existing == null
          ? await remote.create(module: module, name: trimmed, definition: definition)
          : await remote.update(existing.id, definition: definition);
      if (saved == null) return 'Could not save the view.';
      final list = [...state.filters];
      final at = list.indexWhere((f) => f.id == saved.id);
      at >= 0 ? list[at] = saved : list.add(saved);
      state = state.copyWith(filters: list, activeId: saved.id);
      return null;
    } on Object catch (e) {
      return _message(e);
    }
  }

  /// Returns null on success, a user-safe message on failure.
  Future<String?> remove(String id) async {
    final remote = _remote;
    if (remote != null) {
      try {
        await remote.delete(id);
      } on Object catch (e) {
        return _message(e);
      }
    }
    state = SavedFiltersState(
      filters: state.filters.where((f) => f.id != id).toList(),
      activeId: state.activeId == id ? null : state.activeId,
    );
    return null;
  }

  void apply(String id) => state = state.copyWith(activeId: id);

  /// Clear the active marker; the preset stays saved.
  void deactivate() => state = state.copyWith(clearActive: true);

  SavedFilter? _byName(String name) {
    final needle = name.toLowerCase();
    for (final f in state.filters) {
      if (f.name.toLowerCase() == needle) return f;
    }
    return null;
  }

  static String _message(Object e) =>
      e is AppError ? e.message : 'Something went wrong. Please try again.';
}

final _savedFiltersRemoteProvider = Provider<SavedFiltersRemoteDataSource?>((ref) {
  if (!ApiConfig.apiEnabled) return null;
  return SavedFiltersRemoteDataSource(ref.watch(apiServiceProvider));
});

/// Saved-view chips on the Leads list, backed by `/crm/saved-filters/`.
final leadSavedFiltersProvider =
    StateNotifierProvider<SavedFiltersController, SavedFiltersState>(
  (ref) => SavedFiltersController(
    module: 'lead',
    remote: ref.watch(_savedFiltersRemoteProvider),
  ),
);

/// Translates between the Leads drawer and the stored `filter_definition`.
///
/// Rebuilt as each catalog resolves, so a chip applied before they land still
/// decodes correctly once they have — decoding happens at apply time, never at
/// load time, precisely because the catalogs arrive asynchronously.
final leadFilterCodecProvider = Provider<LeadFilterCodec>(
  (ref) => LeadFilterCodec(
    statuses: ref.watch(leadStatusesProvider),
    sources: ref.watch(leadSourcesProvider),
    products: ref.watch(productOptionsProvider),
    teams: ref.watch(teamOptionsProvider),
    currentUserId: UserDirectory.currentUserId,
  ),
);

/// Whether two definitions express the same filter, for deciding if a manual
/// Apply has moved off the active saved view.
bool sameFilterDefinition(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key)) return false;
    if ('${b[e.key]}' != '${e.value}') return false;
  }
  return true;
}
