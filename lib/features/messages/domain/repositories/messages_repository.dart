import '../entities/conversation.dart';

/// Abstract contract for conversation data. The presentation layer depends only
/// on this; mock vs REST is an infrastructure detail.
abstract class MessagesRepository {
  List<Conversation> getConversations();
}
