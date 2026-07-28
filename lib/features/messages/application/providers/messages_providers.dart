import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/repositories/messages_repository.dart';
import '../../infrastructure/data_sources/local/messages_mock_ds.dart';
import '../../infrastructure/repositories/messages_repository_impl.dart';

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final messagesRepositoryProvider = Provider<MessagesRepository>(
  (ref) => const MessagesRepositoryImpl(MessagesMockDataSource()),
);

/// Mutable conversation store. Sending a message / template appends locally
/// (no backend); opening a chat clears its unread count.
class ConversationsController extends StateNotifier<List<Conversation>> {
  ConversationsController(MessagesRepository repo) : super(repo.getConversations());

  void markRead(String id) {
    state = [
      for (final c in state) c.id == id ? c.copyWith(unread: 0) : c,
    ];
  }

  void sendMessage(String id, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _append(id, ChatMessage(mine: true, text: trimmed, time: 'Now', status: 'sent'));
  }

  void sendTemplate(String id, String body) {
    _append(id, ChatMessage(mine: true, text: body, time: 'Now', status: 'sent', tpl: true));
  }

  void _append(String id, ChatMessage msg) {
    state = [
      for (final c in state)
        if (c.id == id)
          c.copyWith(lastTime: 'Now', messages: [...c.messages, msg])
        else
          c,
    ];
  }
}

final conversationsProvider =
    StateNotifierProvider<ConversationsController, List<Conversation>>(
  (ref) => ConversationsController(ref.watch(messagesRepositoryProvider)),
);

/// Look up a single conversation by id (used by the chat screen).
final conversationByIdProvider = Provider.family<Conversation?, String>((ref, id) {
  for (final c in ref.watch(conversationsProvider)) {
    if (c.id == id) return c;
  }
  return null;
});

/// Search query on the Messages list.
final chatSearchProvider = StateProvider<String>((ref) => '');

/// Conversations filtered by the search query (name + company).
final visibleConversationsProvider = Provider<List<Conversation>>((ref) {
  final all = ref.watch(conversationsProvider);
  final q = ref.watch(chatSearchProvider).trim().toLowerCase();
  if (q.isEmpty) return all;
  return all.where((c) => ('${c.name} ${c.company}').toLowerCase().contains(q)).toList();
});

/// Active tab on the chat screen: 'chats' | 'medias' | 'links'.
final chatTabProvider = StateProvider<String>((ref) => 'chats');
