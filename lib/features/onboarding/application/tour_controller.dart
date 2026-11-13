import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_providers.dart';
import '../../../core/storage/app_cache.dart';
import '../../auth/application/providers/auth_providers.dart';
import '../domain/sample_tours.dart';
import '../domain/tour.dart';
import '../infrastructure/onboarding_remote_ds.dart';
import 'tour_event_queue.dart';

/// Build switch, off by default (webapp `VITE_ONBOARDING_TOURS`):
/// `--dart-define=ONBOARDING_TOURS=true`. Off means nothing is fetched,
/// nothing is shown and the Product tours entry is hidden.
const onboardingToursEnabled = bool.fromEnvironment('ONBOARDING_TOURS');

/// Dev aid: `--dart-define=ONBOARDING_SAMPLE_TOUR=true` adds the built-in
/// draft tours while the server has no `mobile` tours published.
const onboardingSampleTours = bool.fromEnvironment('ONBOARDING_SAMPLE_TOUR');

enum TourPhase { idle, invited, running, paused }

class TourState {
  const TourState({
    this.loaded = false,
    this.catalog = const [],
    this.progress = const {},
    this.autoStartEnabled = true,
    this.nextTourKey,
    this.phase = TourPhase.idle,
    this.tourKey,
    this.index = 0,
    this.skipped = const {},
    this.undoTourKey,
    this.offeredThisSession = false,
  });

  final bool loaded;
  final List<Tour> catalog;
  final Map<String, TourProgress> progress;
  final bool autoStartEnabled;
  final String? nextTourKey;

  final TourPhase phase;

  /// The invited / running / paused tour.
  final String? tourKey;

  /// Index into the tour's [Tour.mobileSteps].
  final int index;

  /// Step keys skipped because their target never appeared — not counted in
  /// "2 of 4", so the counter never jumps.
  final Set<String> skipped;

  /// Set while the "Tour skipped · Undo" toast is up.
  final String? undoTourKey;

  /// One auto-offer per app session.
  final bool offeredThisSession;

  Tour? get tour => catalog.where((t) => t.key == tourKey).firstOrNull;

  TourStep? get step {
    final steps = tour?.mobileSteps ?? const <TourStep>[];
    return index >= 0 && index < steps.length ? steps[index] : null;
  }

  /// "2 of 4" over the steps that are actually shown.
  (int, int) get counter {
    final steps = tour?.mobileSteps ?? const <TourStep>[];
    final shown = steps.where((s) => !skipped.contains(s.key)).toList();
    final at = shown.indexWhere((s) => s.key == step?.key);
    return (at < 0 ? 0 : at + 1, shown.length);
  }

  TourState copyWith({
    bool? loaded,
    List<Tour>? catalog,
    Map<String, TourProgress>? progress,
    bool? autoStartEnabled,
    String? Function()? nextTourKey,
    TourPhase? phase,
    String? Function()? tourKey,
    int? index,
    Set<String>? skipped,
    String? Function()? undoTourKey,
    bool? offeredThisSession,
  }) =>
      TourState(
        loaded: loaded ?? this.loaded,
        catalog: catalog ?? this.catalog,
        progress: progress ?? this.progress,
        autoStartEnabled: autoStartEnabled ?? this.autoStartEnabled,
        nextTourKey: nextTourKey != null ? nextTourKey() : this.nextTourKey,
        phase: phase ?? this.phase,
        tourKey: tourKey != null ? tourKey() : this.tourKey,
        index: index ?? this.index,
        skipped: skipped ?? this.skipped,
        undoTourKey: undoTourKey != null ? undoTourKey() : this.undoTourKey,
        offeredThisSession: offeredThisSession ?? this.offeredThisSession,
      );
}

/// Catalog, progress and the one tour on screen. The UI ([TourLayer]) decides
/// *when* (calm moment, target found, route changed); this decides *what*
/// changes, applies it to local progress at once, and queues the server write.
class TourController extends StateNotifier<TourState> {
  TourController(this._ds, this._userId) : super(const TourState()) {
    _queue = TourEventQueue(
      send: _ds.sendEvents,
      load: () => _loadList(_queueKey).map(TourEvent.fromJson).toList(),
      save: (events) =>
          _saveList(_queueKey, [for (final e in events) e.toJson()]),
    );
  }

  final OnboardingRemoteDataSource _ds;
  final String _userId;
  late final TourEventQueue _queue;
  Timer? _undoTimer;

  static const undoWindow = Duration(seconds: 5);

  String get _queueKey => 'onboarding.queue.$_userId';
  String get _localKey => 'onboarding.local.$_userId';

  List<Map<String, dynamic>> _loadList(String key) {
    final v = AppCache.get(AppCache.settingsBox, key)?.data;
    return [
      if (v is List)
        for (final m in v)
          if (m is Map) m.cast<String, dynamic>()
    ];
  }

  void _saveList(String key, List<Map<String, dynamic>> rows) =>
      AppCache.put(AppCache.settingsBox, key, rows);

  /// Reads catalog + progress. Safe to call again (pull to refresh, panel).
  Future<void> load() async {
    var catalog = <Tour>[];
    var snap = const OnboardingSnapshot();
    try {
      final r = await Future.wait([_ds.catalog(), _ds.progress()]);
      catalog = r[0] as List<Tour>;
      snap = r[1] as OnboardingSnapshot;
    } on Object {
      // Tours are an extra: a failed read leaves them off, never an error.
    }
    final progress = {...snap.progress};
    if (onboardingSampleTours && catalog.isEmpty) {
      catalog = [...sampleTours];
      for (final row in _loadList(_localKey)) {
        final p = TourProgress.fromJson(row);
        progress[p.tourKey] = p;
      }
    }
    if (!mounted) return;
    state = state.copyWith(
      loaded: true,
      catalog: catalog,
      progress: progress,
      autoStartEnabled: snap.autoStartEnabled,
      nextTourKey: () => snap.nextTourKey,
    );
  }

  TourProgress _progressOf(Tour t) =>
      state.progress[t.key] ?? TourProgress(tourKey: t.key);

  void _record(Tour tour, TourEventName name, {String? stepKey}) {
    final e = TourEvent(tour.key, tour.version, name, stepKey: stepKey);
    final next = applyTourEvent(_progressOf(tour), tour, e);
    final progress = {...state.progress, tour.key: next};
    state = state.copyWith(
      progress: progress,
      // The server re-picks its suggestion; until it answers, nothing is.
      nextTourKey: () =>
          state.nextTourKey == tour.key ? null : state.nextTourKey,
    );
    if (tour.localOnly) {
      _saveList(_localKey, [
        for (final p in progress.values)
          if (state.catalog.any((t) => t.key == p.tourKey && t.localOnly))
            p.toJson()
      ]);
    } else {
      _queue.add(e);
    }
  }

  // ── offer ──

  Tour? suggestion() => tourToOffer(
        catalog: state.catalog,
        progress: state.progress,
        nextTourKey: state.nextTourKey,
        autoStartEnabled: state.autoStartEnabled,
      );

  void invite(Tour t) {
    if (state.phase != TourPhase.idle) return;
    state = state.copyWith(
        phase: TourPhase.invited,
        tourKey: () => t.key,
        offeredThisSession: true);
  }

  /// "Maybe later": nothing is sent; offered again next session.
  void later() =>
      state = state.copyWith(phase: TourPhase.idle, tourKey: () => null);

  /// ✕ on the invitation: the user does not want it offered again.
  void dismissInvite() {
    final t = state.tour;
    if (t != null) _record(t, TourEventName.dismiss);
    state = state.copyWith(phase: TourPhase.idle, tourKey: () => null);
  }

  // ── run ──

  /// Starts (or resumes) [key]. A finished tour is replayed from the start.
  bool start(String key) {
    final t = state.catalog.where((t) => t.key == key).firstOrNull;
    if (t == null || t.mobileSteps.isEmpty) return false;
    if (prerequisiteMissing(t, state.progress)) return false;
    final p = _progressOf(t);
    if (p.isFinished) {
      _record(t, TourEventName.restart);
    } else if (p.status != TourStatus.inProgress) {
      _record(t, TourEventName.start);
    }
    state = state.copyWith(
      phase: TourPhase.running,
      tourKey: () => t.key,
      index: resumeIndex(t, state.progress[t.key]),
      skipped: const {},
      offeredThisSession: true,
    );
    return true;
  }

  /// The current step is done (Next, tapped target, route changed).
  void next() {
    final t = state.tour;
    final s = state.step;
    if (t == null || s == null) return;
    _record(t, TourEventName.stepCompleted, stepKey: s.key);
    _advance(t);
  }

  /// The current step's target never appeared: count it done, move on.
  void skipMissingStep() {
    final t = state.tour;
    final s = state.step;
    if (t == null || s == null) return;
    state = state.copyWith(skipped: {...state.skipped, s.key});
    _record(t, TourEventName.stepCompleted, stepKey: s.key);
    _advance(t);
  }

  void _advance(Tour t) {
    final last = state.index >= t.mobileSteps.length - 1;
    if (last) {
      _record(t, TourEventName.complete);
      state =
          state.copyWith(phase: TourPhase.idle, tourKey: () => null, index: 0);
    } else {
      state = state.copyWith(index: state.index + 1);
    }
  }

  /// Back is local only: what was completed stays completed.
  void back() {
    if (state.index <= 0) return;
    var i = state.index - 1;
    final steps = state.tour?.mobileSteps ?? const <TourStep>[];
    while (i > 0 && state.skipped.contains(steps[i].key)) {
      i--;
    }
    state = state.copyWith(index: i);
  }

  void pause() {
    if (state.phase == TourPhase.running) {
      state = state.copyWith(phase: TourPhase.paused);
    }
  }

  void resume() {
    if (state.phase == TourPhase.paused) {
      state = state.copyWith(phase: TourPhase.running);
    }
  }

  /// Skip / Esc: the tour closes now; the `skip` is only sent once the Undo
  /// window has passed without Undo.
  void skipTour() {
    final key = state.tourKey;
    if (key == null) return;
    _undoTimer?.cancel();
    final index = state.index;
    state = state.copyWith(
        phase: TourPhase.idle, tourKey: () => null, undoTourKey: () => key);
    _undoTimer = Timer(undoWindow, () {
      if (!mounted || state.undoTourKey != key) return;
      final t = state.catalog.where((t) => t.key == key).firstOrNull;
      if (t != null) _record(t, TourEventName.skip);
      state = state.copyWith(undoTourKey: () => null);
    });
    _undoIndex = index;
  }

  int _undoIndex = 0;

  void undoSkip() {
    final key = state.undoTourKey;
    if (key == null) return;
    _undoTimer?.cancel();
    state = state.copyWith(
        phase: TourPhase.paused,
        tourKey: () => key,
        index: _undoIndex,
        undoTourKey: () => null);
  }

  // ── settings ──

  Future<void> setAutoStart(bool on) async {
    state = state.copyWith(autoStartEnabled: on);
    try {
      await _ds.setAutoStart(on);
    } on Object {
      if (mounted) state = state.copyWith(autoStartEnabled: !on);
      rethrow;
    }
  }

  /// Clears this surface's progress so tours are offered again.
  Future<void> resetAll() async {
    await _queue.flush();
    final hasServerTours = state.catalog.any((t) => !t.localOnly);
    if (hasServerTours) await _ds.reset();
    _saveList(_localKey, const []);
    state = state.copyWith(
        phase: TourPhase.idle,
        tourKey: () => null,
        progress: const {},
        offeredThisSession: false);
    await load();
  }

  Future<void> flush() => _queue.flush();

  @override
  void dispose() {
    _undoTimer?.cancel();
    _queue.dispose();
    super.dispose();
  }
}

final onboardingRemoteDataSourceProvider = Provider<OnboardingRemoteDataSource>(
    (ref) => OnboardingRemoteDataSource(() => ref.read(apiServiceProvider)));

/// One controller per signed-in user; rebuilt (and reloaded) on a user switch.
final tourControllerProvider =
    StateNotifierProvider<TourController, TourState>((ref) {
  final userId =
      ref.watch(sessionControllerProvider.select((s) => s.user?.id ?? ''));
  final c =
      TourController(ref.watch(onboardingRemoteDataSourceProvider), userId);
  if (onboardingToursEnabled && userId.isNotEmpty) c.load();
  return c;
});
