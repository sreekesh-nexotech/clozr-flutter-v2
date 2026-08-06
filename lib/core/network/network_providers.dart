import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/token_storage.dart';
import 'api_service.dart';

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
