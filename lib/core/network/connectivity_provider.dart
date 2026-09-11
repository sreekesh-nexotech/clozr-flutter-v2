import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device currently has a network interface up (wifi or mobile
/// data) — the OS-level signal, not a check that the backend is actually
/// reachable. That is deliberate: it is what lets the UI react the instant
/// wifi/data is switched off, rather than waiting for some request to be
/// attempted and time out first. A live server outage while the radio is
/// still up is still caught, just by the existing per-request `AppError`
/// path ([AppErrorType.network] / [AppErrorType.timeout]) — this provider is
/// only for the "no interface at all" case that path cannot see coming.
///
/// `AsyncLoading` only very briefly on cold start, while the first
/// [Connectivity.checkConnectivity] call resolves; everything downstream
/// treats "still loading" the same as "don't know yet, say nothing".
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield _isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(_isOnline);
});

bool _isOnline(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);
