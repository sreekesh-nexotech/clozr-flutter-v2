import 'package:flutter/widgets.dart';

/// Every target id the app defines. A published `mobile` tour that points at
/// an id missing from this list can never highlight anything — the unit test
/// checks the built-in tours against it, and authors can use it as the menu
/// of what exists (webapp `check:tour-anchors`).
abstract final class TourAnchors {
  // Shell — on every list / home screen.
  static const tabs = 'nav.tabs';
  static const apps = 'nav.apps';
  static const messages = 'topbar.messages';
  static const notifications = 'topbar.notifications';
  static const add = 'action.add';

  // Lists: `<area>.list`, `<area>.search`, `<area>.filters`.
  static const leadsList = 'leads.list';
  static const leadsSearch = 'leads.search';
  static const leadsFilters = 'leads.filters';
  static const tasksList = 'tasks.list';
  static const tasksSearch = 'tasks.search';
  static const tasksFilters = 'tasks.filters';
  static const ticketsList = 'tickets.list';
  static const ticketsSearch = 'tickets.search';
  static const ticketsFilters = 'tickets.filters';

  static const all = <String>{
    tabs, apps, messages, notifications, add, //
    leadsList, leadsSearch, leadsFilters,
    tasksList, tasksSearch, tasksFilters,
    ticketsList, ticketsSearch, ticketsFilters,
  };

  /// Bottom-nav tabs are also addressable one by one: `nav.tab.<key>`
  /// (`nav.tab.leads`, `nav.tab.tasks`, …).
  static String tab(String key) => 'nav.tab.$key';

  static bool isKnown(String id) =>
      all.contains(id) || id.startsWith('nav.tab.');
}

/// Where each mounted anchor is, so a tour step can find it by id.
class TourAnchorRegistry {
  TourAnchorRegistry._();
  static final instance = TourAnchorRegistry._();

  final Map<String, List<_TourAnchorState>> _byId = {};

  /// Ticks whenever an anchor mounts or unmounts.
  final ValueNotifier<int> changes = ValueNotifier(0);

  /// Taps on an anchor, for `advance: click_target`.
  final ValueNotifier<String?> lastTap = ValueNotifier(null);

  void _add(String id, _TourAnchorState s) {
    (_byId[id] ??= []).add(s);
    changes.value++;
  }

  void _remove(String id, _TourAnchorState s) {
    _byId[id]?.remove(s);
    if (_byId[id]?.isEmpty ?? false) _byId.remove(id);
    changes.value++;
  }

  BuildContext? contextOf(String id) {
    for (final s in (_byId[id] ?? const <_TourAnchorState>[]).reversed) {
      if (s.mounted && _visibleRect(s.context) != null) return s.context;
    }
    return null;
  }

  /// The anchor's on-screen rectangle (global coordinates), or null when it
  /// is not mounted, has no size, or sits off screen.
  Rect? rectOf(String id) {
    for (final s in (_byId[id] ?? const <_TourAnchorState>[]).reversed) {
      if (!s.mounted) continue;
      final r = _visibleRect(s.context);
      if (r != null) return r;
    }
    return null;
  }

  static Rect? _visibleRect(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (box.size.isEmpty) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }
}

/// Marks [child] as the tour target [id]. Mark the *purpose*, not the widget:
/// `leads.list` goes on whichever of the list or the board is showing.
class TourAnchor extends StatefulWidget {
  const TourAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<TourAnchor> createState() => _TourAnchorState();
}

class _TourAnchorState extends State<TourAnchor> {
  @override
  void initState() {
    super.initState();
    TourAnchorRegistry.instance._add(widget.id, this);
  }

  @override
  void didUpdateWidget(TourAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      TourAnchorRegistry.instance._remove(old.id, this);
      TourAnchorRegistry.instance._add(widget.id, this);
    }
  }

  @override
  void dispose() {
    TourAnchorRegistry.instance._remove(widget.id, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        // Observes only — the child still gets the tap.
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) => TourAnchorRegistry.instance.lastTap.value =
            '${widget.id}#${DateTime.now().microsecondsSinceEpoch}',
        child: widget.child,
      );
}
