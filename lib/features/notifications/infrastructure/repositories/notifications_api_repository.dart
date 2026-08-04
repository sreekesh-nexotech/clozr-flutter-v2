import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../data_sources/remote/notifications_remote_ds.dart';

/// REST-backed [NotificationsRepository]. The feed caches its raw JSON rows in
/// Hive as a network-down fallback; mutations are remote-only and best-effort
/// (the controller applied the optimistic update already, and these calls are
/// fired unawaited — they must never surface as unhandled async errors).
class NotificationsApiRepository implements NotificationsRepository {
  NotificationsApiRepository(this._remote);

  final NotificationsRemoteDataSource _remote;

  static const _box = AppCache.notificationsCache;
  static const _key = 'feed';

  @override
  Future<List<AppNotification>> getNotifications() async {
    try {
      final rows = await _remote.fetchNotificationRows();
      await AppCache.put(_box, _key, rows);
      return _remote.mapRows(rows);
    } on AppError catch (e) {
      if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
        final cached = AppCache.get(_box, _key)?.data;
        if (cached is List) return _remote.mapRows(cached);
      }
      rethrow;
    }
  }

  @override
  Future<void> markRead(String id, bool read) async {
    // The API has no mark-unread endpoint — unread stays a local-only toggle.
    if (!read) return;
    try {
      await _remote.markRead(id);
    } on AppError {
      // Best-effort; the next feed refresh reconciles.
    }
  }

  @override
  Future<void> markAllRead() async {
    try {
      await _remote.markAllRead();
    } on AppError {
      // Best-effort; the next feed refresh reconciles.
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _remote.delete(id);
    } on AppError {
      // Best-effort; the next feed refresh reconciles.
    }
  }
}
