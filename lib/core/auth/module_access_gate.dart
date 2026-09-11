import 'package:flutter/foundation.dart';

import '../../features/auth/domain/entities/module_access.dart';

/// A plain [ChangeNotifier] bridge between `moduleAccessProvider` and
/// GoRouter's `refreshListenable`/`redirect` — mirrors [SessionGate] so the
/// router can react to the role becoming known without importing Riverpod.
///
/// [access] carries the same "unknown vs. known-and-empty" distinction as the
/// provider it mirrors: null before the first fetch resolves (or for mock
/// mode / a failed fetch), non-null once a real `/auth/me/modules/` response
/// has landed. [loaded] is what tells a reader which of those it's looking
/// at — `access == null` alone can't, since a failed fetch also reports null.
class ModuleAccessGate extends ChangeNotifier {
  ModuleAccessGate._();

  static final ModuleAccessGate instance = ModuleAccessGate._();

  bool _loaded = false;
  ModuleAccess? _access;

  bool get loaded => _loaded;
  ModuleAccess? get access => _access;

  /// A fetch settled (with or without a usable result).
  void set(ModuleAccess? next) {
    _loaded = true;
    _access = next;
    notifyListeners();
  }

  /// Back to "unknown" — logout, or a session that isn't authenticated yet.
  /// No [notifyListeners]: this only ever fires alongside a [SessionGate]
  /// transition that already triggers the router's redirect on its own.
  void reset() {
    _loaded = false;
    _access = null;
  }
}
