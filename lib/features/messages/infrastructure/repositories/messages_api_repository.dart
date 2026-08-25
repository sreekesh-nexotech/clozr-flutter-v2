import '../../../../core/network/app_error.dart';
import '../../../../core/storage/app_cache.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/whatsapp_template.dart';
import '../../domain/repositories/messages_repository.dart';
import '../data_sources/remote/messages_remote_ds.dart';

/// REST-backed [MessagesRepository]. Reads cache the raw JSON rows in Hive and
/// re-map them when the network is down; writes are remote-only and
/// best-effort (the controller has already applied the optimistic update, so
/// a failed fire-and-forget send must never crash an unawaited future).
class MessagesApiRepository implements MessagesRepository {
  MessagesApiRepository(this._remote);

  final MessagesRemoteDataSource _remote;

  static const _box = AppCache.crmCache;
  static const _conversationsKey = 'whatsapp_conversations';
  static const _templatesKey = 'whatsapp_templates';
  static String _messagesKey(String id) => 'whatsapp_messages_$id';

  bool _offline(AppError e) =>
      e.type == AppErrorType.network || e.type == AppErrorType.timeout;

  @override
  Future<List<Conversation>> getConversations() async {
    try {
      final rows = await _remote.fetchConversationRows();
      await AppCache.put(_box, _conversationsKey, rows);
      return _remote.mapConversationRows(rows);
    } on AppError catch (e) {
      if (_offline(e)) {
        final cached = AppCache.get(_box, _conversationsKey)?.data;
        if (cached is List) return _remote.mapConversationRows(cached);
      }
      rethrow;
    }
  }

  @override
  Future<ChatThread> getThread(String conversationId) async {
    try {
      final rows = await _remote.fetchMessageRows(conversationId);
      await AppCache.put(_box, _messagesKey(conversationId), rows);
      return _remote.mapThreadRows(rows);
    } on AppError catch (e) {
      if (_offline(e)) {
        final cached = AppCache.get(_box, _messagesKey(conversationId))?.data;
        if (cached is List) return _remote.mapThreadRows(cached);
      }
      rethrow;
    }
  }

  @override
  Future<void> markRead(String conversationId) async {
    try {
      await _remote.markRead(conversationId);
    } on AppError {
      // Best-effort: the local badge is already cleared.
    }
  }

  @override
  Future<ChatMessage?> sendText(String conversationId, String text) async {
    try {
      return await _remote.sendText(conversationId, text);
    } on AppError {
      return null;
    }
  }

  @override
  Future<ChatMessage?> sendTemplate(
      String conversationId, String templateId, String body) async {
    try {
      return await _remote.sendTemplate(conversationId, templateId, body);
    } on AppError {
      return null;
    }
  }

  @override
  Future<List<WhatsappTemplate>> getTemplates() async {
    try {
      final rows = await _remote.fetchTemplateRows();
      await AppCache.put(_box, _templatesKey, rows);
      return _remote.mapTemplateRows(rows);
    } on AppError catch (e) {
      if (_offline(e)) {
        final cached = AppCache.get(_box, _templatesKey)?.data;
        if (cached is List) return _remote.mapTemplateRows(cached);
      }
      rethrow;
    }
  }
}
