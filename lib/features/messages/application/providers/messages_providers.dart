import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
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

/// Immutable conversation-list UI state: the rows plus a load phase. In API
/// mode a failed initial fetch stores the [error] so the screen can show a
/// retry; in mock mode the fetch never fails, so the phase stays clean.
class ConversationsState {
  const ConversationsState({
    this.conversations = const [],
    this.loading = false,
    this.error,
  });

  final List<Conversation> conversations;
  final bool loading;
  final AppError? error;

  ConversationsState copyWith({
    List<Conversation>? conversations,
    bool? loading,
    AppError? error,
    bool clearError = false,
  }) =>
      ConversationsState(
        conversations: conversations ?? this.conversations,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Mutable conversation store. In API mode it seeds a loading phase (never
/// mock) and stores a failure so the list can offer a retry; in mock mode it
/// seeds empty and loads the seed exactly as before (no loading/error surface).
/// Sending a message / template and opening a chat update the list
/// optimistically first, then fire the matching repository call — the send
/// result is threaded back so a rejected bubble is marked `failed` (audit M3).
class ConversationsController extends StateNotifier<ConversationsState> {
  ConversationsController(this._repo,
      {List<WhatsappTemplate> Function()? templates})
      : _templates = templates,
        super(ConversationsState(loading: ApiConfig.apiEnabled)) {
    _start();
  }

  final MessagesRepository _repo;
  final List<WhatsappTemplate> Function()? _templates;

  /// The load in flight, so a caller that needs the list *now* — opening a
  /// lead's WhatsApp thread from the CRM, where nothing has rendered the
  /// Messages tab yet — can await the same fetch instead of racing it.
  Future<void>? _inFlight;

  int _localSeq = 0;
  String _nextLocalId() => 'local-${_localSeq++}';

  Future<void> _load() async {
    if (ApiConfig.apiEnabled) state = state.copyWith(loading: true, clearError: true);
    try {
      final conversations = await _repo.getConversations();
      if (mounted) state = state.copyWith(conversations: conversations, loading: false, clearError: true);
    } on AppError catch (e) {
      // Mock never throws; in API mode surface the failure for a retry.
      if (mounted) state = state.copyWith(loading: false, error: e);
    } on Object catch (e) {
      if (mounted) {
        state = state.copyWith(
          loading: false,
          error: AppError(type: AppErrorType.unknown, message: 'Something went wrong. Please try again.', cause: e),
        );
      }
    }
  }

  /// Retry the conversation-list fetch (used by the error-state Retry CTA).
  void reload() => _start();

  Future<void> _start() =>
      _inFlight ??= _load().whenComplete(() => _inFlight = null);

  /// Resolves once the conversation list has been loaded at least once.
  ///
  /// Returns immediately when rows are already in hand; otherwise it joins the
  /// load in flight, or starts one (which is also what happens after a failed
  /// or genuinely empty fetch — a lead opened minutes later deserves a fresh
  /// look before the UI concludes there is no thread).
  Future<void> ensureLoaded() {
    if (state.conversations.isNotEmpty) return Future.value();
    return _start();
  }

  void markRead(String id) {
    state = state.copyWith(conversations: [
      for (final c in state.conversations) c.id == id ? c.copyWith(unread: 0) : c,
    ]);
    unawaited(_repo.markRead(id));
    // The API list rows carry only a last-message preview; opening a chat is
    // the moment its real thread gets pulled in.
    if (ApiConfig.apiEnabled) unawaited(_refreshMessages(id));
  }

  void sendMessage(String id, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final localId = _nextLocalId();
    _append(id, ChatMessage(mine: true, text: trimmed, time: 'Now', status: 'sent', localId: localId));
    unawaited(_dispatchText(id, localId, trimmed));
  }

  void sendTemplate(String id, String body) {
    final localId = _nextLocalId();
    _append(id, ChatMessage(mine: true, text: body, time: 'Now', status: 'sent', tpl: true, localId: localId));
    unawaited(_dispatchTemplate(id, localId, body));
  }

  /// Uploads and sends a picked file. [isImage] picks `/send/image/` vs
  /// `/send/document/` — the two are separate endpoints server-side, each with
  /// its own size/type validation, so the caller must already know which kind
  /// of file it staged.
  void sendAttachment(String id, String path, String filename, {required bool isImage}) {
    final localId = _nextLocalId();
    _append(
      id,
      ChatMessage(
        mine: true,
        text: filename,
        time: 'Now',
        status: 'sent',
        localId: localId,
        attachmentPath: path,
        attachmentKind: isImage ? 'image' : 'document',
      ),
    );
    unawaited(_dispatchAttachment(id, localId, path, filename, isImage: isImage));
  }

  /// Re-fire a bubble that came back rejected. Resets it to optimistic, then
  /// dispatches again on the same path (text vs template vs attachment).
  void retryMessage(String conversationId, ChatMessage failed) {
    final localId = failed.localId;
    if (localId == null) return;
    _setStatus(conversationId, localId, 'sent');
    if (failed.isAttachment) {
      unawaited(_dispatchAttachment(
        conversationId,
        localId,
        failed.attachmentPath!,
        failed.text,
        isImage: failed.attachmentKind == 'image',
      ));
    } else if (failed.tpl) {
      unawaited(_dispatchTemplate(conversationId, localId, failed.text));
    } else {
      unawaited(_dispatchText(conversationId, localId, failed.text));
    }
  }

  Future<void> _dispatchText(String id, String localId, String text) async {
    final sent = await _repo.sendText(id, text);
    if (!mounted) return;
    _setStatus(id, localId, sent != null ? _statusOf(sent) : 'failed');
  }

  Future<void> _dispatchTemplate(String id, String localId, String body) async {
    final sent = await _repo.sendTemplate(id, _templateIdForBody(id, body), body);
    if (!mounted) return;
    _setStatus(id, localId, sent != null ? _statusOf(sent) : 'failed');
  }

  /// Downloads an attachment through the authenticated media proxy, for
  /// opening a message whose local file is gone (a later session, a cleared
  /// cache) — see [ChatMessage.mediaId].
  Future<(List<int>, String?)?> fetchMedia(String mediaId) => _repo.fetchMedia(mediaId);

  Future<void> _dispatchAttachment(
      String id, String localId, String path, String filename,
      {required bool isImage}) async {
    final sent = isImage
        ? await _repo.sendImage(id, path, filename)
        : await _repo.sendDocument(id, path, filename);
    if (!mounted) return;
    _setStatus(id, localId, sent != null ? _statusOf(sent) : 'failed');
  }

  String _statusOf(ChatMessage m) => m.status.isNotEmpty ? m.status : 'sent';

  /// Reconcile a send result onto its optimistic bubble (matched by localId).
  void _setStatus(String conversationId, String localId, String status) {
    state = state.copyWith(conversations: [
      for (final c in state.conversations)
        if (c.id == conversationId)
          c.copyWith(messages: [
            for (final m in c.messages) m.localId == localId ? m.copyWith(status: status) : m,
          ])
        else
          c,
    ]);
  }

  Future<void> _refreshMessages(String id) async {
    try {
      final thread = await _repo.getThread(id);
      if (!mounted) return;
      state = state.copyWith(conversations: [
        for (final c in state.conversations)
          if (c.id == id)
            c.copyWith(
              messages: [
                ...thread.messages,
                // Keep optimistic sends that raced the fetch.
                ...c.messages.where((m) => m.mine && m.time == 'Now'),
              ],
              // The Medias and Links tabs read the same fetch — before this
              // they were only ever filled by the prototype seed, so both
              // reported "nothing shared" on every real conversation.
              media: thread.media,
              links: thread.links,
            )
          else
            c,
      ]);
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
    for (final c in state.conversations) {
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
    state = state.copyWith(conversations: [
      for (final c in state.conversations)
        if (c.id == id)
          c.copyWith(lastTime: 'Now', messages: [...c.messages, msg])
        else
          c,
    ]);
  }
}

final conversationsProvider =
    StateNotifierProvider<ConversationsController, ConversationsState>((ref) {
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
  for (final c in ref.watch(conversationsProvider).conversations) {
    if (c.id == id) return c;
  }
  return null;
});

/// The conversation for a CRM record, matched the two ways the API allows:
/// its `lead` link first, then the contact's number.
///
/// The number matters as much as the link — WhatsApp threads are created by the
/// inbound webhook from a phone number, and `lead` is only set once the backend
/// has matched that number to a record. A thread that started before the lead
/// existed (or against a second number on the same lead) carries no link at all
/// and would otherwise look like "no conversation".
Conversation? findConversationForLead(
  List<Conversation> conversations, {
  required String leadId,
  required String phone,
}) {
  for (final c in conversations) {
    if (c.leadId != null && c.leadId == leadId) return c;
  }
  if (phone.trim().isEmpty) return null;
  for (final c in conversations) {
    if (c.phone.isNotEmpty && sameWaNumber(c.phone, phone)) return c;
  }
  return null;
}

/// Search query on the Messages list.
final chatSearchProvider = StateProvider<String>((ref) => '');

/// Conversations filtered by the search query (name + company).
final visibleConversationsProvider = Provider<List<Conversation>>((ref) {
  final all = ref.watch(conversationsProvider).conversations;
  final q = ref.watch(chatSearchProvider).trim().toLowerCase();
  if (q.isEmpty) return all;
  return all.where((c) => ('${c.name} ${c.company}').toLowerCase().contains(q)).toList();
});

/// Active tab on the chat screen: 'chats' | 'medias' | 'links'.
final chatTabProvider = StateProvider<String>((ref) => 'chats');

/// Async bridge for the approved-template list (remote fetch in API mode).
/// In API mode a genuinely empty result stays empty — the const seed is a
/// MOCK-only source and is never used to paper over a real fetch (audit L-10).
final _remoteWhatsappTemplatesProvider =
    FutureProvider<List<WhatsappTemplate>>((ref) async {
  if (!ApiConfig.apiEnabled) return kWhatsappTemplates;
  return ref.watch(messagesRepositoryProvider).getTemplates();
});

/// Approved WhatsApp templates offered by the closed-window picker. Read
/// synchronously by the chat screen. Mock mode serves the const seed; API mode
/// serves the fetched list (empty until it lands / when there are none) — never
/// the seed.
final whatsappTemplatesProvider = Provider<List<WhatsappTemplate>>((ref) {
  if (!ApiConfig.apiEnabled) return kWhatsappTemplates;
  return ref.watch(_remoteWhatsappTemplatesProvider).asData?.value ??
      const <WhatsappTemplate>[];
});

/// Whether the approved-template fetch is still in flight (API mode only). The
/// picker shows a loading state instead of the seed while this is true.
final whatsappTemplatesLoadingProvider = Provider<bool>((ref) {
  if (!ApiConfig.apiEnabled) return false;
  return ref.watch(_remoteWhatsappTemplatesProvider).isLoading;
});
