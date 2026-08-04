import 'package:flutter/foundation.dart';

/// Auth phase the router branches on.
enum SessionStatus {
  /// Restoring tokens from secure storage at startup.
  restoring,

  /// No valid session — show the login flow.
  unauthenticated,

  /// Signed in.
  authenticated,
}

/// A plain [ChangeNotifier] bridge between the auth controller and GoRouter's
/// `refreshListenable`/`redirect` — the router stays free of Riverpod imports.
/// The session controller is the only writer.
class SessionGate extends ChangeNotifier {
  SessionGate._();

  static final SessionGate instance = SessionGate._();

  SessionStatus _status = SessionStatus.restoring;

  SessionStatus get status => _status;

  void set(SessionStatus next) {
    if (next == _status) return;
    _status = next;
    notifyListeners();
  }
}
