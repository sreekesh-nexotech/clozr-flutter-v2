import '../entities/app_notification.dart';

/// Abstract contract for the notifications feed. The controller depends only
/// on this; mock vs REST is an infrastructure detail.
abstract class NotificationsRepository {
  Future<List<AppNotification>> getNotifications();

  /// Marks one notification read ([read] == true) or unread. The backend only
  /// supports marking read — an unread request is a local-only toggle and
  /// implementations may no-op it.
  Future<void> markRead(String id, bool read);

  Future<void> markAllRead();

  Future<void> delete(String id);
}
