import 'package:flutter/widgets.dart';

/// How many dialogs / bottom sheets / menus are open, across the root and the
/// shell navigator. A tour is never offered over one, and a running tour
/// pauses when one opens (webapp: overlays are detected by `aria-modal`).
///
/// A [NavigatorObserver] can watch one navigator only, so each navigator gets
/// its own [observer()]; they share this count.
class TourPopupTracker {
  TourPopupTracker._();
  static final instance = TourPopupTracker._();

  final ValueNotifier<int> open = ValueNotifier(0);

  NavigatorObserver observer() => _PopupObserver(this);

  void _delta(Route<dynamic>? route, int by) {
    if (route is PopupRoute) {
      final v = open.value + by;
      open.value = v < 0 ? 0 : v;
    }
  }
}

class _PopupObserver extends NavigatorObserver {
  _PopupObserver(this._t);
  final TourPopupTracker _t;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _t._delta(route, 1);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _t._delta(route, -1);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _t._delta(route, -1);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _t._delta(oldRoute, -1);
    _t._delta(newRoute, 1);
  }
}
