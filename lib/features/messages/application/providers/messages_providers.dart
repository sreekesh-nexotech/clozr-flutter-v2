import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/whatsapp_template.dart';
import '../../domain/repositories/messages_repository.dart';
import '../../infrastructure/data_sources/local/messages_mock_ds.dart';
import '../../infrastructure/data_sources/remote/messages_remote_ds.dart';
import '../../infrastructure/repositories/messages_api_repository.dart';
import '../../infrastructure/repositories/messages_repository_impl.dart';

/// DI seam: mock seed without a base URL, REST otherwise.
final messagesRepositoryProvider = Provider<MessagesRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const MessagesRepositoryImpl(MessagesMockDataSource());
  }
  return MessagesApiRepository(
    MessagesRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Mutable conversation store. State seeds asynchronously from the repository;
/// sending a message / template and opening a chat update the list
/// optimistically first, then fire the matching repository call unawaited.
class ConversationsController extends StateNotifier<List<Conversation>> {
  ConversationsController(this._repo,
      {List<WhatsappTemplate> Function()? templates})
      : _templates = templates,
        super(const []) {
    _load();
  }

  final MessagesRepository _repo;
  final List<WhatsappTemplate> Function()? _templates;

  Future<void> _load() async {
    try {
      final conversations = await _repo.getConversations();
      if (mounted) state = conversations;
    } on Object {
      // The list simply stays empty when the fetch fails.
    }
  }

  void markRead(String id) {
    state = [
      for (final c in state) c.id == id ? c.copyWith(unread: 0) : c,
    ];
    unawaited(_repo.markRead(id));
    // The API list rows carry only a last-message preview; opening a chat is
    // the moment its real thread gets pulled in.
    if (ApiConfig.apiEnabled) unawaited(_refreshMessages(id));
  }

  void sendMessage(String id, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _append(id, ChatMessage(mine: true, text: trimmed, time: 'Now', status: 'sent'));
    unawaited(_repo.sendText(id, trimmed));
  }

  void sendTemplate(String id, String body) {
    _append(id, ChatMessage(mine: true, text: body, time: 'Now', status: 'sent', tpl: true));
    unawaited(_repo.sendTemplate(id, _templateIdForBody(id, body), body));
  }

  Future<void> _refreshMessages(String id) async {
    try {
      final fetched = await _repo.getMessages(id);
      if (!mounted) return;
      state = [
        for (final c in state)
          if (c.id == id)
            c.copyWith(messages: [
              ...fetched,
              // Keep optimistic sends that raced the fetch.
              ...c.messages.where((m) => m.mine && m.time == 'Now'),
            ])
          else
            c,
      ];
    } on Object {
      // Keep the preview row; a failed thread fetch is never fatal.
    }
  }

  /// The chat screen hands over only the resolved body — recover which
  /// template it was by resolving each known template against the contact's
  /// first name, exactly like the picker preview did.
  String _templateIdForBody(String conversationId, String body) {
    final templates = _templates?.call() ?? const <WhatsappTemplate>[];
    var firstName = '';
    for (final c in state) {
      if (c.id == conversationId) {
        firstName = c.name.split(' ').first;
        break;
      }
    }
    for (final t in templates) {
      if (t.resolve(firstName) == body || t.body == body) return t.id;
    }
    return '';
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
    StateNotifierProvider<ConversationsController, List<Conversation>>((ref) {
  if (ApiConfig.apiEnabled) {
    // Warm the template cache so the picker has real templates by the time
    // the first closed-window chat is opened.
    ref.read(_remoteWhatsappTemplatesProvider);
  }
  return ConversationsController(
    ref.watch(messagesRepositoryProvider),
    templates: () => ref.read(whatsappTemplatesProvider),
  );
});

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

/// Async bridge for the approved-template list (remote fetch in API mode).
final _remoteWhatsappTemplatesProvider =
    FutureProvider<List<WhatsappTemplate>>((ref) async {
  if (!ApiConfig.apiEnabled) return kWhatsappTemplates;
  final fetched = await ref.watch(messagesRepositoryProvider).getTemplates();
  return fetched.isEmpty ? kWhatsappTemplates : fetched;
});

/// Approved WhatsApp templates offered by the closed-window picker. Stays a
/// synchronous Provider (the chat screen reads it directly): it serves the
/// const seed until the remote fetch lands, then the fetched list.
final whatsappTemplatesProvider = Provider<List<WhatsappTemplate>>((ref) {
  return ref.watch(_remoteWhatsappTemplatesProvider).asData?.value ??
      kWhatsappTemplates;
});
