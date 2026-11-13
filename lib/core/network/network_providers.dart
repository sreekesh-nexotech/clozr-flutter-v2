import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/token_storage.dart';
import 'api_service.dart';
import 'app_error.dart';
import 'approval_hold.dart';
import 'mandatory_course_block.dart';

/// App-wide token store. Overridable in tests with an in-memory fake.
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// The single network gateway every remote data source receives via DI.
final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(tokens: ref.watch(tokenStorageProvider)),
);

/// Mirrors [ApiService.writes] into a provider, coalescing bursts.
///
/// One user action is often several writes — a note POST then its attachment
/// upload, a create then a follow-up refresh — and each would otherwise be its
/// own refetch. Waiting out a short quiet period turns a burst into one tick.
class _WriteTicker extends StateNotifier<int> {
  _WriteTicker(this._source) : super(_source.value) {
    _source.addListener(_onWrite);
  }

  final ValueListenable<int> _source;
  Timer? _debounce;

  static const _quiet = Duration(milliseconds: 300);

  void _onWrite() {
    _debounce?.cancel();
    _debounce = Timer(_quiet, () {
      if (mounted) state = _source.value;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // The notifier belongs to [ApiService] and outlives this — detach, never
    // dispose it.
    _source.removeListener(_onWrite);
    super.dispose();
  }
}

/// Ticks after any successful write, anywhere in the app.
///
/// Watch it from anything that must reflect a change it did not itself make.
final apiWriteTickProvider = StateNotifierProvider<_WriteTicker, int>(
  (ref) => _WriteTicker(ref.watch(apiServiceProvider).writes),
);

/// Mirrors [ApiService.failures] into a provider, coalescing bursts.
///
/// A screen opens several calls at once — a list, its layout, two or three
/// option catalogs — and a role that cannot read one of them often cannot read
/// its siblings either. Without the quiet period that is three or four
/// refusals arriving as separate messages for what the user experiences as one
/// action, so the last one within the window wins.
class _FailureWatcher extends StateNotifier<AppError?> {
  _FailureWatcher(this._source) : super(null) {
    _source.addListener(_onFailure);
  }

  final ValueListenable<AppError?> _source;
  Timer? _debounce;

  static const _quiet = Duration(milliseconds: 400);

  void _onFailure() {
    _debounce?.cancel();
    _debounce = Timer(_quiet, () {
      if (mounted) state = _source.value;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Belongs to [ApiService] and outlives this — detach, never dispose it.
    _source.removeListener(_onFailure);
    super.dispose();
  }
}

/// The latest failure worth reporting from anywhere in the app — every rejected
/// write, plus any 403 — carrying the backend's own message.
///
/// Listened to once, in the shell, so a refusal is always reported, including
/// the ones no screen would otherwise surface.
final apiFailureProvider = StateNotifierProvider<_FailureWatcher, AppError?>(
  (ref) => _FailureWatcher(ref.watch(apiServiceProvider).failures),
);

/// Mirrors [ApiService.courseBlocks] — the latest mandatory-course 403 and
/// its incomplete courses. Listened to once, in the shell, which raises the
/// app-wide blocking screen from it.
class _CourseBlockWatcher extends StateNotifier<List<IncompleteCourse>?> {
  _CourseBlockWatcher(this._source) : super(null) {
    _source.addListener(_onBlock);
  }

  final ValueListenable<List<IncompleteCourse>?> _source;

  void _onBlock() {
    if (mounted) state = _source.value;
  }

  @override
  void dispose() {
    // Belongs to [ApiService] and outlives this — detach, never dispose it.
    _source.removeListener(_onBlock);
    super.dispose();
  }
}

final apiCourseBlockProvider =
    StateNotifierProvider<_CourseBlockWatcher, List<IncompleteCourse>?>(
  (ref) => _CourseBlockWatcher(ref.watch(apiServiceProvider).courseBlocks),
);

/// Mirrors [ApiService.holds] — writes the server held for approval.
///
/// Delivered a beat late on purpose: the screen that made the save usually
/// toasts its own "Saved" straight after the await, and the held-for-approval
/// sentence has to be the one left on screen, since the record did not change.
class _HoldWatcher extends StateNotifier<ApprovalHold?> {
  _HoldWatcher(this._source) : super(null) {
    _source.addListener(_onHold);
  }

  final ValueListenable<ApprovalHold?> _source;
  Timer? _debounce;

  static const _settle = Duration(milliseconds: 350);

  void _onHold() {
    final hold = _source.value;
    if (hold == null) return;
    _debounce?.cancel();
    _debounce = Timer(_settle, () {
      if (mounted) state = hold;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Belongs to [ApiService] and outlives this — detach, never dispose it.
    _source.removeListener(_onHold);
    super.dispose();
  }
}

/// The latest write held for approval, anywhere in the app. Listened to once,
/// in the shell.
final apiApprovalHoldProvider =
    StateNotifierProvider<_HoldWatcher, ApprovalHold?>(
  (ref) => _HoldWatcher(ref.watch(apiServiceProvider).holds),
);
