import 'dart:async';
import 'dart:math' as math;

import '../../../core/network/app_error.dart';
import '../domain/tour.dart';

/// Sends one tour's batch of events.
typedef TourEventSender = Future<void> Function(
    String tourKey, int tourVersion, List<TourEvent> events);

/// Tour progress is written in the background so the tour never waits on the
/// network (webapp `ProgressQueue`):
///
/// * events are held for [debounce] and sent together, at most [maxBatch] per
///   request, grouped by tour and version, in the order they happened;
/// * a network failure or a 5xx keeps the batch and retries with back-off;
/// * a 4xx means the server will never accept it (unknown tour, stale
///   version) — it is dropped so it cannot block the events behind it;
/// * the unsent list is saved through [save] after every change and handed
///   back by [load] on the next start, so closing the app loses nothing.
class TourEventQueue {
  TourEventQueue({
    required TourEventSender send,
    List<TourEvent> Function()? load,
    void Function(List<TourEvent>)? save,
    this.debounce = const Duration(milliseconds: 400),
    this.maxBatch = 50,
  })  : _send = send,
        _save = save {
    _pending.addAll(load?.call() ?? const []);
    if (_pending.isNotEmpty) _schedule(Duration.zero);
  }

  final TourEventSender _send;
  final void Function(List<TourEvent>)? _save;
  final Duration debounce;
  final int maxBatch;

  final List<TourEvent> _pending = [];
  Timer? _timer;
  bool _sending = false;
  int _failures = 0;
  bool _closed = false;

  List<TourEvent> get pending => List.unmodifiable(_pending);

  void add(TourEvent e) {
    if (_closed) return;
    _pending.add(e);
    _persist();
    _schedule(debounce);
  }

  /// Sends what is queued now (app going to the background).
  Future<void> flush() async {
    _timer?.cancel();
    await _drain();
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
  }

  void _schedule(Duration after) {
    if (_closed) return;
    _timer?.cancel();
    _timer = Timer(after, _drain);
  }

  void _persist() => _save?.call(List.of(_pending));

  Future<void> _drain() async {
    if (_sending || _closed) return;
    _sending = true;
    try {
      while (_pending.isNotEmpty && !_closed) {
        final first = _pending.first;
        final batch = <TourEvent>[];
        for (final e in _pending) {
          if (e.tourKey != first.tourKey ||
              e.tourVersion != first.tourVersion) {
            break;
          }
          batch.add(e);
          if (batch.length == maxBatch) break;
        }
        try {
          await _send(first.tourKey, first.tourVersion, batch);
          _pending.removeRange(0, batch.length);
          _failures = 0;
          _persist();
        } on AppError catch (e) {
          if (_isPermanent(e)) {
            _pending.removeRange(0, batch.length);
            _persist();
            continue;
          }
          _retryLater();
          return;
        } on Object {
          _retryLater();
          return;
        }
      }
    } finally {
      _sending = false;
    }
  }

  static bool _isPermanent(AppError e) {
    final code = e.statusCode ?? 0;
    return code >= 400 &&
        code < 500 &&
        code != 401 &&
        code != 408 &&
        code != 429;
  }

  void _retryLater() {
    _failures++;
    final secs = math.min(60, 2 * math.pow(2, _failures - 1).toInt());
    _schedule(Duration(seconds: secs));
  }
}
