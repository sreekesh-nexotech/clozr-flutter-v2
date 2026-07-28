import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/app_notification.dart';
import '../../infrastructure/data_sources/local/notifications_mock_ds.dart';

const _pageSize = 8;
const _pageStep = 6;

enum NotifFilter { all, unread }

/// Immutable notifications UI state.
class NotificationsState {
  final List<AppNotification> all;
  final NotifFilter filter;
  final int shown;
  final bool loading;

  const NotificationsState({
    required this.all,
    this.filter = NotifFilter.all,
    this.shown = _pageSize,
    this.loading = true,
  });

  NotificationsState copyWith({
    List<AppNotification>? all,
    NotifFilter? filter,
    int? shown,
    bool? loading,
  }) =>
      NotificationsState(
        all: all ?? this.all,
        filter: filter ?? this.filter,
        shown: shown ?? this.shown,
        loading: loading ?? this.loading,
      );

  static const _dayRank = {'today': 0, 'yesterday': 1, 'earlier': 2};

  /// All notifications matching the active filter, sorted by day then order.
  List<AppNotification> get filtered {
    final list = filter == NotifFilter.unread ? all.where((n) => n.unread).toList() : List.of(all);
    list.sort((a, b) => (_dayRank[a.day] ?? 3).compareTo(_dayRank[b.day] ?? 3));
    return list;
  }

  List<AppNotification> get visible => filtered.take(shown).toList();

  int get unreadCount => all.where((n) => n.unread).length;
  bool get hasMore => shown < filtered.length;
  int get remaining => filtered.length - shown;

  /// Count of items for a given day within the current filter (for headers).
  int dayCount(String day) => filtered.where((n) => n.day == day).length;
}

class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this._ds) : super(NotificationsState(all: const [], loading: true)) {
    _load();
  }

  final NotificationsMockDataSource _ds;
  Timer? _timer;

  Future<void> _load() async {
    state = state.copyWith(loading: true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () {
      state = state.copyWith(all: _ds.fetch(), loading: false);
    });
  }

  void refresh() {
    state = state.copyWith(shown: _pageSize);
    _load();
  }

  void setFilter(NotifFilter f) => state = state.copyWith(filter: f, shown: _pageSize);

  void markAllRead() =>
      state = state.copyWith(all: [for (final n in state.all) n.copyWith(unread: false)]);

  void toggleRead(String id) => state = state.copyWith(
        all: [for (final n in state.all) n.id == id ? n.copyWith(unread: !n.unread) : n],
      );

  void markRead(String id) => state = state.copyWith(
        all: [for (final n in state.all) n.id == id ? n.copyWith(unread: false) : n],
      );

  void delete(String id) =>
      state = state.copyWith(all: state.all.where((n) => n.id != id).toList());

  void loadMore() => state = state.copyWith(shown: state.shown + _pageStep);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>(
  (ref) => NotificationsController(const NotificationsMockDataSource()),
);
