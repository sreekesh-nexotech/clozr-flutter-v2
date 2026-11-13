/// Product tours — the shapes of `/api/v1/onboarding/` (the webapp's
/// `docs/backend/ONBOARDING_FRONTEND.md`), read for the `mobile` surface.
///
/// Optional step fields are omitted by the server when an author did not set
/// them; every default is applied here, in one place, so nothing downstream
/// has to guess.
library;

/// Which app's tours these are. The webapp reads `default`; the phone layout
/// has no sidebar or top bar, so its tours are authored separately.
const kTourSurface = 'mobile';

enum TourPlacement { auto, top, bottom, left, right, center }

enum TourAdvance { next, clickTarget, routeChange }

enum TourStatus { notStarted, inProgress, completed, skipped, dismissed }

TourPlacement _placement(Object? v) => switch (v) {
      'top' => TourPlacement.top,
      'bottom' => TourPlacement.bottom,
      'left' => TourPlacement.left,
      'right' => TourPlacement.right,
      'center' => TourPlacement.center,
      _ => TourPlacement.auto,
    };

TourAdvance _advance(Object? v) => switch (v) {
      'click_target' => TourAdvance.clickTarget,
      'route_change' => TourAdvance.routeChange,
      _ => TourAdvance.next,
    };

TourStatus tourStatusOf(Object? v) => switch (v) {
      'in_progress' => TourStatus.inProgress,
      'completed' => TourStatus.completed,
      'skipped' => TourStatus.skipped,
      'dismissed' => TourStatus.dismissed,
      _ => TourStatus.notStarted,
    };

String _s(Object? v) => v is String ? v : (v == null ? '' : '$v');
int _i(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0;
bool _b(Object? v) => v == true;

class TourStep {
  const TourStep({
    required this.key,
    required this.route,
    required this.title,
    this.target = '',
    this.body = '',
    this.placement = TourPlacement.auto,
    this.advance = TourAdvance.next,
    this.optional = false,
    this.desktopOnly = false,
  });

  factory TourStep.fromJson(Map<String, dynamic> j) => TourStep(
        key: _s(j['key']),
        route: _s(j['route']),
        target: _s(j['target']),
        title: _s(j['title']),
        body: _s(j['body']),
        placement: _placement(j['placement']),
        advance: _advance(j['advance']),
        optional: _b(j['optional']),
        desktopOnly: _b(j['desktop_only']),
      );

  final String key;
  final String route;

  /// A [TourAnchor] id; empty for a centred card.
  final String target;
  final String title;
  final String body;
  final TourPlacement placement;
  final TourAdvance advance;
  final bool optional;

  /// Web-only steps — always skipped on the phone.
  final bool desktopOnly;

  bool get isCentered => placement == TourPlacement.center || target.isEmpty;
}

class Tour {
  const Tour({
    required this.key,
    required this.version,
    required this.title,
    required this.steps,
    this.majorVersion = 1,
    this.description = '',
    this.category = '',
    this.order = 0,
    this.autoStart = false,
    this.startRoute = '',
    this.prerequisite,
    this.localOnly = false,
  });

  factory Tour.fromJson(Map<String, dynamic> j) => Tour(
        key: _s(j['key']),
        version: _i(j['version']),
        majorVersion: _i(j['major_version']),
        title: _s(j['title']),
        description: _s(j['description']),
        category: _s(j['category']),
        order: _i(j['order']),
        autoStart: j['trigger'] == 'auto_first_visit',
        startRoute: _s(j['start_route']),
        prerequisite: _s(j['prerequisite_tour']).isEmpty
            ? null
            : _s(j['prerequisite_tour']),
        steps: [
          for (final s in (j['steps'] as List? ?? const []))
            if (s is Map) TourStep.fromJson(s.cast<String, dynamic>()),
        ],
      );

  final String key;
  final int version;
  final int majorVersion;
  final String title;
  final String description;
  final String category;
  final int order;

  /// `trigger: auto_first_visit` — may be offered without being asked for.
  final bool autoStart;
  final String startRoute;
  final String? prerequisite;

  /// A built-in sample tour the server does not know: progress stays on the
  /// phone and no events are sent.
  final bool localOnly;

  final List<TourStep> steps;

  /// The steps that can run on a phone, in order.
  List<TourStep> get mobileSteps =>
      steps.where((s) => !s.desktopOnly).toList(growable: false);
}

class TourProgress {
  const TourProgress({
    required this.tourKey,
    this.tourVersion = 0,
    this.status = TourStatus.notStarted,
    this.currentStepKey = '',
    this.completedSteps = const [],
    this.replayCount = 0,
    this.outdated = false,
  });

  factory TourProgress.fromJson(Map<String, dynamic> j) => TourProgress(
        tourKey: _s(j['tour_key']),
        tourVersion: _i(j['tour_version']),
        status: tourStatusOf(j['status']),
        currentStepKey: _s(j['current_step_key']),
        completedSteps: [
          for (final k in (j['completed_steps'] as List? ?? const [])) _s(k)
        ],
        replayCount: _i(j['replay_count']),
        outdated: _b(j['outdated']),
      );

  Map<String, dynamic> toJson() => {
        'tour_key': tourKey,
        'tour_version': tourVersion,
        'status': switch (status) {
          TourStatus.notStarted => 'not_started',
          TourStatus.inProgress => 'in_progress',
          TourStatus.completed => 'completed',
          TourStatus.skipped => 'skipped',
          TourStatus.dismissed => 'dismissed',
        },
        'current_step_key': currentStepKey,
        'completed_steps': completedSteps,
        'replay_count': replayCount,
        'outdated': outdated,
      };

  final String tourKey;
  final int tourVersion;
  final TourStatus status;
  final String currentStepKey;
  final List<String> completedSteps;
  final int replayCount;
  final bool outdated;

  bool get isFinished =>
      status == TourStatus.completed ||
      status == TourStatus.skipped ||
      status == TourStatus.dismissed;

  TourProgress copyWith({
    int? tourVersion,
    TourStatus? status,
    String? currentStepKey,
    List<String>? completedSteps,
    int? replayCount,
    bool? outdated,
  }) =>
      TourProgress(
        tourKey: tourKey,
        tourVersion: tourVersion ?? this.tourVersion,
        status: status ?? this.status,
        currentStepKey: currentStepKey ?? this.currentStepKey,
        completedSteps: completedSteps ?? this.completedSteps,
        replayCount: replayCount ?? this.replayCount,
        outdated: outdated ?? this.outdated,
      );
}

/// The events the server accepts, by their wire names.
enum TourEventName {
  start('start'),
  stepCompleted('step_completed'),
  complete('complete'),
  skip('skip'),
  dismiss('dismiss'),
  restart('restart');

  const TourEventName(this.wire);
  final String wire;
}

class TourEvent {
  const TourEvent(this.tourKey, this.tourVersion, this.name, {this.stepKey});

  factory TourEvent.fromJson(Map<String, dynamic> j) => TourEvent(
        _s(j['tour_key']),
        _i(j['tour_version']),
        TourEventName.values.firstWhere((e) => e.wire == j['event'],
            orElse: () => TourEventName.stepCompleted),
        stepKey: _s(j['step_key']).isEmpty ? null : _s(j['step_key']),
      );

  final String tourKey;
  final int tourVersion;
  final TourEventName name;
  final String? stepKey;

  Map<String, dynamic> toJson() => {
        'tour_key': tourKey,
        'tour_version': tourVersion,
        'event': name.wire,
        if (stepKey != null) 'step_key': stepKey,
      };

  /// The body item the server takes inside `events: [...]`.
  Map<String, dynamic> toWire() =>
      {'event': name.wire, if (stepKey != null) 'step_key': stepKey};
}

/// Applies one event to a tour's progress the way the server does, so the
/// screen never waits for the network to know where the user is.
TourProgress applyTourEvent(TourProgress p, Tour tour, TourEvent e) {
  switch (e.name) {
    case TourEventName.start:
      return p.copyWith(
          tourVersion: tour.version,
          status: TourStatus.inProgress,
          currentStepKey: tour.mobileSteps.isEmpty
              ? ''
              : (p.currentStepKey.isNotEmpty
                  ? p.currentStepKey
                  : tour.mobileSteps.first.key));
    case TourEventName.restart:
      return p.copyWith(
          tourVersion: tour.version,
          status: TourStatus.inProgress,
          completedSteps: const [],
          currentStepKey:
              tour.mobileSteps.isEmpty ? '' : tour.mobileSteps.first.key,
          replayCount: p.replayCount + 1,
          outdated: false);
    case TourEventName.stepCompleted:
      final done = {...p.completedSteps, if (e.stepKey != null) e.stepKey!};
      final ordered = [
        for (final s in tour.steps)
          if (done.contains(s.key)) s.key
      ];
      final next = tour.mobileSteps
          .where((s) => !done.contains(s.key))
          .map((s) => s.key)
          .firstOrNull;
      return p.copyWith(
          tourVersion: tour.version,
          status: TourStatus.inProgress,
          completedSteps: ordered,
          currentStepKey: next ?? '');
    case TourEventName.complete:
      return p.copyWith(
          status: TourStatus.completed, currentStepKey: '', outdated: false);
    case TourEventName.skip:
      return p.copyWith(status: TourStatus.skipped, currentStepKey: '');
    case TourEventName.dismiss:
      return p.copyWith(status: TourStatus.dismissed, currentStepKey: '');
  }
}

/// Where in [tour] a run should begin: the first step not yet completed, or
/// the start when everything is done (a replay).
int resumeIndex(Tour tour, TourProgress? p) {
  final steps = tour.mobileSteps;
  if (p == null || p.status != TourStatus.inProgress) return 0;
  final i = steps.indexWhere((s) => !p.completedSteps.contains(s.key));
  return i < 0 ? 0 : i;
}

/// The tour to offer on its own, or null. The server's `next_tour_key` wins
/// for server tours (it already honours opt-out, prerequisites and
/// eligibility); a local sample tour is offered when it was never seen.
Tour? tourToOffer({
  required List<Tour> catalog,
  required Map<String, TourProgress> progress,
  required String? nextTourKey,
  required bool autoStartEnabled,
}) {
  if (!autoStartEnabled) return null;
  if (nextTourKey != null) {
    final t = catalog.where((t) => t.key == nextTourKey).firstOrNull;
    if (t != null && t.mobileSteps.isNotEmpty) return t;
  }
  for (final t in catalog) {
    if (!t.localOnly || !t.autoStart || t.mobileSteps.isEmpty) continue;
    final p = progress[t.key];
    if (p == null || p.status == TourStatus.notStarted) return t;
  }
  return null;
}

/// Whether [prerequisite] blocks starting [tour].
bool prerequisiteMissing(Tour tour, Map<String, TourProgress> progress) {
  final pre = tour.prerequisite;
  if (pre == null) return false;
  return progress[pre]?.status != TourStatus.completed;
}

/// Route comparison for a step: the path only (no query); a route written
/// with `:id`-style segments matches by its fixed prefix.
bool routeMatches(String stepRoute, String location) {
  final path = location.split('?').first.split('#').first;
  final want = stepRoute.split('?').first;
  if (want.isEmpty) return true;
  final colon = want.indexOf('/:');
  if (colon >= 0) return path.startsWith(want.substring(0, colon));
  return path == want;
}
