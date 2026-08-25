import '../../domain/entities/conversation.dart';
import '../../domain/entities/whatsapp_template.dart';
import '../../domain/repositories/messages_repository.dart';
import '../data_sources/local/messages_mock_ds.dart';

/// Mock-backed implementation. Wraps the synchronous seed in Futures so the
/// interface matches the REST repository — the callers stay the same.
class MessagesRepositoryImpl implements MessagesRepository {
  const MessagesRepositoryImpl(this._local);

  final MessagesMockDataSource _local;

  @override
  Future<List<Conversation>> getConversations() async =>
      _local.fetchConversations();

  @override
  Future<ChatThread> getThread(String conversationId) async {
    for (final c in _local.fetchConversations()) {
      if (c.id == conversationId) {
        return ChatThread(messages: c.messages, media: c.media, links: c.links);
      }
    }
    return const ChatThread();
  }

  @override
  Future<void> markRead(String conversationId) async {
    // Local-only in mock mode; the controller already zeroed the badge.
  }

  @override
  Future<ChatMessage?> sendText(String conversationId, String text) async =>
      ChatMessage(mine: true, text: text, time: 'Now', status: 'sent');

  @override
  Future<ChatMessage?> sendTemplate(
          String conversationId, String templateId, String body) async =>
      ChatMessage(mine: true, text: body, time: 'Now', status: 'sent', tpl: true);

  @override
  Future<List<WhatsappTemplate>> getTemplates() async => kWhatsappTemplates;
}
