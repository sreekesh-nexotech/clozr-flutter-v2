import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../../infrastructure/data_sources/local/notifications_mock_ds.dart';
import '../../infrastructure/data_sources/remote/notifications_remote_ds.dart';
import '../../infrastructure/repositories/notifications_api_repository.dart';
import '../../infrastructure/repositories/notifications_repository_impl.dart';

const _pageSize = 8;
const _pageStep = 6;

enum NotifFilter { all, unread }

/// DI seam: mock seed without a base URL, REST otherwise.
final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const NotificationsRepositoryImpl(NotificationsMockDataSource());
  }
  return NotificationsApiRepository(
    NotificationsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

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

/// Mutations update local state optimistically, then fire the matching
/// repository call unawaited (the mock repository no-ops them).
class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this._repo)
      : super(const NotificationsState(all: [], loading: true)) {
    _load();
  }

  final NotificationsRepository _repo;

  Future<void> _load() async {
    state = state.copyWith(loading: true);
    try {
      final rows = await _repo.getNotifications();
      if (mounted) state = state.copyWith(all: rows, loading: false);
    } on Object {
      // Keep whatever is on screen; just stop the shimmer.
      if (mounted) state = state.copyWith(loading: false);
    }
  }

  void refresh() {
    state = state.copyWith(shown: _pageSize);
    _load();
  }

  void setFilter(NotifFilter f) => state = state.copyWith(filter: f, shown: _pageSize);

  void markAllRead() {
    state = state.copyWith(all: [for (final n in state.all) n.copyWith(unread: false)]);
    unawaited(_repo.markAllRead());
  }

  void toggleRead(String id) {
    AppNotification? target;
    for (final n in state.all) {
      if (n.id == id) {
        target = n;
        break;
      }
    }
    if (target == null) return;
    final becomesRead = target.unread;
    state = state.copyWith(
      all: [for (final n in state.all) n.id == id ? n.copyWith(unread: !n.unread) : n],
    );
    unawaited(_repo.markRead(id, becomesRead));
  }

  void markRead(String id) {
    state = state.copyWith(
      all: [for (final n in state.all) n.id == id ? n.copyWith(unread: false) : n],
    );
    unawaited(_repo.markRead(id, true));
  }

  void delete(String id) {
    state = state.copyWith(all: state.all.where((n) => n.id != id).toList());
    unawaited(_repo.delete(id));
  }

  void loadMore() => state = state.copyWith(shown: state.shown + _pageStep);
}

final notificationsProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>(
  (ref) => NotificationsController(ref.watch(notificationsRepositoryProvider)),
);
