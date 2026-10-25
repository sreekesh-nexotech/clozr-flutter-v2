import '../entities/app_notification.dart';

/// Abstract contract for the notifications feed. The controller depends only
/// on this; mock vs REST is an infrastructure detail.
abstract class NotificationsRepository {
  /// [status] is the webapp's segment filter: null (All), `unread`, `pinned`
  /// or `snoozed`.
  Future<List<AppNotification>> getNotifications({String? status});

  /// Marks one notification read ([read] == true) or unread. The backend only
  /// supports marking read — an unread request is a local-only toggle and
  /// implementations may no-op it.
  Future<void> markRead(String id, bool read);

  Future<void> markAllRead();

  Future<void> delete(String id);

  /// Pin or unpin. Unlike the best-effort calls above these throw, so the
  /// screen can say when the server refused.
  Future<void> setPinned(String id, bool pinned);

  /// Snooze until [until], or unsnooze when null. Throws on failure.
  Future<void> setSnoozed(String id, DateTime? until);

  /// Unread count for the bell.
  Future<int> unreadCount();
}
