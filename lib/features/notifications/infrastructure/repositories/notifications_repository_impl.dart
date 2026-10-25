import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../data_sources/local/notifications_mock_ds.dart';

/// Mock-backed implementation wrapping the static seed. The short delay keeps
/// the loading shimmer visible in mock mode, exactly as before the repository
/// existed; mutations are harmless no-ops (the controller owns local state).
class NotificationsRepositoryImpl implements NotificationsRepository {
  const NotificationsRepositoryImpl(this._local);

  final NotificationsMockDataSource _local;

  @override
  Future<List<AppNotification>> getNotifications({String? status}) =>
      Future.delayed(const Duration(milliseconds: 500), () {
        final all = _local.fetch();
        return switch (status) {
          'unread' => all.where((n) => n.unread).toList(),
          'pinned' || 'snoozed' => const <AppNotification>[],
          _ => all,
        };
      });

  @override
  Future<void> markRead(String id, bool read) async {}

  @override
  Future<void> markAllRead() async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> setPinned(String id, bool pinned) async {}

  @override
  Future<void> setSnoozed(String id, DateTime? until) async {}

  @override
  Future<int> unreadCount() async => _local.fetch().where((n) => n.unread).length;
}
