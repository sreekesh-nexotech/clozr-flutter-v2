import '../../../core/network/api_service.dart';
import '../domain/tour.dart';

/// The server's view of a user's tours on this surface.
class OnboardingSnapshot {
  const OnboardingSnapshot({
    this.progress = const {},
    this.autoStartEnabled = true,
    this.nextTourKey,
  });

  final Map<String, TourProgress> progress;
  final bool autoStartEnabled;
  final String? nextTourKey;
}

/// `/api/v1/onboarding/` — the same calls the webapp makes, with
/// `surface=mobile`. Every write is a background write: tour bookkeeping must
/// never refresh the lists or raise a toast.
class OnboardingRemoteDataSource {
  /// Looked up per call: the app replaces its [ApiService] on reconnect, and a
  /// running tour must not be torn down with it.
  OnboardingRemoteDataSource(this._apiOf);
  final ApiService Function() _apiOf;
  ApiService get _api => _apiOf();

  static const _base = '/onboarding';

  Future<List<Tour>> catalog() async {
    final body = await _api.get('$_base/catalog/',
        query: {'surface': kTourSurface}, quiet: true);
    final list = body is Map ? body['tours'] : body;
    if (list is! List) return const [];
    final tours = [
      for (final t in list)
        if (t is Map) Tour.fromJson(t.cast<String, dynamic>())
    ]..sort((a, b) => a.order.compareTo(b.order));
    return tours;
  }

  Future<OnboardingSnapshot> progress() async {
    final body = await _api.get('$_base/progress/',
        query: {'surface': kTourSurface}, quiet: true);
    if (body is! Map) return const OnboardingSnapshot();
    return parseSnapshot(body.cast<String, dynamic>());
  }

  static OnboardingSnapshot parseSnapshot(Map<String, dynamic> body) {
    final rows = body['progress'];
    final prefs = body['preferences'];
    final next = body['next_tour_key'];
    return OnboardingSnapshot(
      progress: {
        if (rows is List)
          for (final r in rows)
            if (r is Map)
              '${r['tour_key']}':
                  TourProgress.fromJson(r.cast<String, dynamic>()),
      },
      autoStartEnabled:
          prefs is Map ? prefs['auto_start_enabled'] != false : true,
      nextTourKey: next is String && next.isNotEmpty ? next : null,
    );
  }

  /// One tour's batch. The server answers with that tour's updated progress.
  Future<void> sendEvents(
      String tourKey, int tourVersion, List<TourEvent> events) async {
    await _api.post('$_base/events/',
        body: {
          'surface': kTourSurface,
          'tour_key': tourKey,
          'tour_version': tourVersion,
          'events': [for (final e in events) e.toWire()],
        },
        background: true);
  }

  Future<void> setAutoStart(bool enabled) async {
    await _api.patch('$_base/preferences/',
        body: {'auto_start_enabled': enabled}, background: true);
  }

  Future<void> reset() async {
    await _api.post('$_base/reset/',
        body: {'surface': kTourSurface}, background: true);
  }
}
