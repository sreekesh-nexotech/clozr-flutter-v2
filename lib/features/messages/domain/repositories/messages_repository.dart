import '../entities/conversation.dart';
import '../entities/whatsapp_template.dart';

/// Abstract contract for conversation data. The presentation layer depends only
/// on this; mock vs REST is an infrastructure detail. All methods are async so
/// the REST implementation slots in without touching callers.
abstract class MessagesRepository {
  Future<List<Conversation>> getConversations();

  /// The latest page of the conversation's thread, oldest-first — with the
  /// files and links it contains, which the Medias and Links tabs render.
  Future<ChatThread> getThread(String conversationId);

  /// Clears the conversation's unread count server-side. Best-effort.
  Future<void> markRead(String conversationId);

  /// Sends a free-form text (24h window open). Returns the sent message, or
  /// null when the send could not be performed.
  Future<ChatMessage?> sendText(String conversationId, String text);

  /// Sends an approved template message (window closed). [body] is the
  /// already-resolved preview text shown in the thread.
  Future<ChatMessage?> sendTemplate(
      String conversationId, String templateId, String body);

  /// Approved WhatsApp templates for the closed-window picker.
  Future<List<WhatsappTemplate>> getTemplates();
}
