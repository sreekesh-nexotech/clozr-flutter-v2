import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'filter_models.dart';

/// A named snapshot of a filter combination — the "saved view" that appears as
/// a bookmark chip above a list. Applying it loads [values] as the current
/// filter state (so reopening the drawer shows those attributes, editable).
class SavedView {
  const SavedView({required this.id, required this.name, required this.values});

  final String id;
  final String name;
  final FilterValues values;

  SavedView copyWith({String? name, FilterValues? values}) =>
      SavedView(id: id, name: name ?? this.name, values: values ?? this.values);
}

/// State held per list key: the saved views plus which one (if any) is applied.
class SavedViewsState {
  const SavedViewsState({this.views = const [], this.activeId});

  final List<SavedView> views;
  final String? activeId;

  SavedView? get active {
    for (final v in views) {
      if (v.id == activeId) return v;
    }
    return null;
  }

  SavedViewsState copyWith({List<SavedView>? views, String? activeId, bool clearActive = false}) =>
      SavedViewsState(
        views: views ?? this.views,
        activeId: clearActive ? null : (activeId ?? this.activeId),
      );
}

/// Controller for one list's saved views. A module creates one
/// [StateNotifierProvider] per list key and drives it from its screen:
///
/// * [upsert] — capture the current draft as a new view, or update the
///   same-named one ("Save view" / "Update view"). Marks it active.
/// * [apply] — mark a view active. The screen then copies the view's values
///   into its applied-filter provider so the drawer reflects them.
/// * [deactivate] — a manual Apply from the drawer clears the active view
///   without deleting it (mirrors the prototype `deactivateViews`).
/// * [remove] / [clearActive].
class SavedViewsController extends StateNotifier<SavedViewsState> {
  SavedViewsController([SavedViewsState? initial]) : super(initial ?? const SavedViewsState());

  var _seq = 0;
  String _newId() => 'view_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  /// Add a new view, or replace an existing one with the same (case-insensitive)
  /// name. Returns the stored view (marked active).
  SavedView upsert(String name, FilterValues values) {
    final trimmed = name.trim();
    final snapshot = values.copy();
    final existing = state.views.indexWhere((v) => v.name.toLowerCase() == trimmed.toLowerCase());
    if (existing >= 0) {
      final updated = state.views[existing].copyWith(values: snapshot);
      final list = [...state.views]..[existing] = updated;
      state = state.copyWith(views: list, activeId: updated.id);
      return updated;
    }
    final view = SavedView(id: _newId(), name: trimmed, values: snapshot);
    state = state.copyWith(views: [...state.views, view], activeId: view.id);
    return view;
  }

  void apply(String id) => state = state.copyWith(activeId: id);

  void remove(String id) {
    state = SavedViewsState(
      views: state.views.where((v) => v.id != id).toList(),
      activeId: state.activeId == id ? null : state.activeId,
    );
  }

  /// Clear the active marker (view stays saved). Called when the user applies
  /// manual filters from the drawer.
  void deactivate() => state = state.copyWith(clearActive: true);

  void clearActive() => deactivate();
}
