import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/whatsapp_template.dart';

// ─────────────────────────────────────────────────────────────────────────────
// JSON → entity mappers (top-level so the unit tests can exercise them without
// an ApiService). All reads are defensive: a malformed row maps to null and is
// skipped, never fatal.
// ─────────────────────────────────────────────────────────────────────────────

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// A related object's pk as a string, whichever way the API serialises it
/// (int, uuid string, or a nested `{id: ...}` object). Null when absent.
String? _pk(Object? v) {
  if (v == null) return null;
  if (v is Map) return _pk(v['id']);
  if (v is String) return _str(v);
  if (v is num) return v.toString();
  return null;
}

String _clockLabel(DateTime? time) =>
    time == null ? '' : DateFormat('h:mm a').format(time.toLocal());

/// The composer's 24h-window label from `is_window_open`/`window_expires_at`.
///
/// - Neither field present → `'24h'` (no window info at all: keep the composer
///   usable; the send endpoint re-checks anyway).
/// - `is_window_open == false` → null (closed, template-only composer).
/// - Open with a future expiry → `'14h 22m left'`-style countdown.
/// - Open but no/expired expiry (clock skew) → `'24h'` (trust the server flag).
String? windowLeftFromJson(Map<String, dynamic> row, {DateTime? now}) {
  final hasFlag = row.containsKey('is_window_open');
  final hasExpiry = row.containsKey('window_expires_at');
  if (!hasFlag && !hasExpiry) return '24h';
  final open = row['is_window_open'];
  if (open == false) return null;
  final expires = parseApiDate(row['window_expires_at']);
  if (expires == null) return open == true ? '24h' : null;
  final left = expires.difference(now ?? DateTime.now());
  if (left <= Duration.zero) return open == true ? '24h' : null;
  final h = left.inHours;
  final m = left.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m left' : '${m}m left';
}

/// One `/whatsapp/conversations/` row → [Conversation]. The pk is an INT —
/// stringified into the entity id. The row carries only a last-message preview,
/// so the thread starts as a single synthetic message (the real thread is
/// fetched lazily when the chat is opened).
Conversation? conversationFromJson(Map<String, dynamic> row, {DateTime? now}) {
  final pk = row['id'];
  if (pk == null) return null;
  final id = pk.toString();

  final name = _str(row['wa_contact_name']) ??
      _str(row['lead_name']) ??
      _str(row['contact_name']) ??
      _str(row['wa_contact_phone']) ??
      'Unknown';

  String company = '';
  for (final key in const ['lead_name', 'contact_name', 'wa_contact_phone']) {
    final v = _str(row[key]);
    if (v != null && v != name) {
      company = v;
      break;
    }
  }

  final lastAt = parseApiDate(row['last_message_at'] ?? row['updated_at']);

  final preview = _str(row['last_message_preview']);
  final messages = <ChatMessage>[
    // Synthetic preview row so the list subtitle shows the real last message
    // before the thread loads. mine=false keeps the server's own "You: "
    // prefix (already baked into the preview) from doubling up.
    if (preview != null)
      ChatMessage(mine: false, text: preview, time: _clockLabel(lastAt)),
  ];

  return Conversation(
    id: id,
    // `lead` is the linked CRM record. It is a pk, not necessarily a string —
    // an int one used to map to null here, which quietly cost every
    // integer-keyed org the lead ⇄ conversation link.
    leadId: _pk(row['lead']),
    phone: waDigits(_str(row['wa_contact_phone']) ?? ''),
    name: name,
    company: company,
    initials: UserDirectory.initialsOf(name),
    online: false,
    unread: (row['unread_count'] as num?)?.toInt() ?? 0,
    windowLeft: windowLeftFromJson(row, now: now),
    lastTime: relativeTime(lastAt, now: now),
    messages: messages,
  );
}

/// One `/conversations/{id}/messages/` row → [ChatMessage].
ChatMessage? chatMessageFromJson(Map<String, dynamic> row) {
  final type = _str(row['message_type']);
  final text = _str(row['body']) ??
      _str(row['text']) ??
      (type == null ? null : '[$type]');
  if (text == null) return null;

  final mine = row['direction'] == 'outbound' || row['is_from_me'] == true;
  final rawStatus = _str(row['status'])?.toLowerCase();
  final status = !mine
      ? ''
      : rawStatus == 'read'
          ? 'read'
          : (rawStatus == 'sent' || rawStatus == 'delivered')
              ? 'sent'
              : '';

  return ChatMessage(
    mine: mine,
    text: text,
    time: _clockLabel(parseApiDate(row['timestamp'] ?? row['created_at'])),
    status: status,
    tpl: type == 'template' || _str(row['template_name']) != null,
    // Never populated on a fresh optimistic send — only a fetched row carries
    // this (`whatsapp.md` §5: outbound rows store `media_id`, never `media_url`).
    mediaId: (type == 'image' || type == 'document') ? _str(row['media_id']) : null,
  );
}

/// One message row → a "Medias" tab entry, or null when the row carries no
/// file.
///
/// The rows already say everything the tab needs (`media_url`,
/// `media_mime_type`, `message_type`), so the tab is a second reading of the
/// thread rather than another endpoint. It used to be filled only by the
/// prototype seed, which meant every real conversation reported "No media
/// shared" however many files had been exchanged.
///
/// `media_url` is checked first but is empty on nearly every real row —
/// WhatsApp inbound messages arrive with only a `media_id`, resolved later
/// through the authenticated media proxy (same id [chatMessageFromJson]
/// stores for the chat bubble). Falling back to it here is what makes the
/// tab actually list anything on a real conversation.
ChatMedia? chatMediaFromJson(Map<String, dynamic> row, {DateTime? now}) {
  final url = _str(row['media_url']);
  final mediaId = _str(row['media_id']);
  if (url == null && mediaId == null) return null;
  final type = _str(row['message_type'])?.toLowerCase() ?? '';
  final mime = _str(row['media_mime_type']) ?? '';
  final sent = parseApiDate(row['timestamp'] ?? row['created_at']);

  // The caption is the human name when WhatsApp sends one; otherwise the file
  // name off the URL when there is one; otherwise the kind of thing it is.
  final name = _str(row['caption']) ??
      _str(row['file_name']) ??
      (url != null ? _fileNameOf(url) : null) ??
      (type.isEmpty ? 'Attachment' : '${type[0].toUpperCase()}${type.substring(1)}');

  final kind = mime.isNotEmpty
      ? mime.split('/').last.toUpperCase()
      : (type.isEmpty ? 'FILE' : type.toUpperCase());

  return ChatMedia(
    kind: mediaKind(type, mime),
    name: name,
    meta: [kind, relativeTime(sent, now: now)].where((s) => s.isNotEmpty).join(' · '),
    mediaId: mediaId,
  );
}

/// The file name in a media URL, ignoring any query string.
String? _fileNameOf(String url) {
  final clean = url.split('?').first;
  final seg = clean.substring(clean.lastIndexOf('/') + 1);
  return seg.isEmpty ? null : seg;
}

/// The [ChatMedia.kind] for a row, by WhatsApp's own message type first and its
/// mime second — the same two fields the send path uses.
///
/// A string rather than an icon on purpose: the icon set lives in the
/// presentation layer, and reaching for it here would drag its package into
/// every consumer of this mapper.
String mediaKind(String type, String mime) {
  final m = mime.toLowerCase();
  if (type == 'image' || m.startsWith('image/')) return 'image';
  if (type == 'video' || m.startsWith('video/')) return 'video';
  if (type == 'audio' || type == 'voice' || m.startsWith('audio/')) return 'audio';
  if (m.contains('pdf')) return 'pdf';
  if (m.contains('sheet') || m.contains('excel') || m.contains('csv')) return 'sheet';
  if (m.contains('word') || m.contains('document')) return 'doc';
  return 'file';
}

/// URLs shared in a message body → "Links" tab entries.
///
/// A body can carry more than one, so this answers a list. Bare `www.` links
/// count: people paste them, and the tab is about what was shared rather than
/// what happens to be clickable.
List<ChatLink> chatLinksFromJson(Map<String, dynamic> row, {DateTime? now}) {
  final body = _str(row['body']) ?? _str(row['text']);
  if (body == null) return const [];
  final sent = relativeTime(parseApiDate(row['timestamp'] ?? row['created_at']), now: now);

  final out = <ChatLink>[];
  for (final match in _urlPattern.allMatches(body)) {
    final raw = match.group(0)!;
    // Trailing sentence punctuation is not part of the address.
    final url = raw.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');
    if (url.isEmpty) continue;
    out.add(ChatLink(title: _linkTitle(url), url: url, meta: sent));
  }
  return out;
}

final _urlPattern =
    RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);

/// The row's bold line: the host, plus the first path segment when there is
/// one — "kairali.in/work" reads better than the whole query string.
String _linkTitle(String url) {
  var clean = url.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  clean = clean.split('?').first;
  final parts = clean.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return clean;
  return parts.length == 1 ? parts.first : '${parts[0]}/${parts[1]}';
}

/// One `/whatsapp/templates/` row → [WhatsappTemplate]. The body is the BODY
/// component's text with Meta's first numbered slot (`{{1}}`) rewritten to the
/// UI's `{name}` placeholder so the picker preview personalises.
WhatsappTemplate? whatsappTemplateFromJson(Map<String, dynamic> row) {
  final pk = row['id'] ?? row['template_id'];
  final rawName = _str(row['name']);
  if (pk == null || rawName == null) return null;

  String body = '';
  final components = row['components'];
  if (components is List) {
    for (final c in components) {
      if (c is Map && (c['type']?.toString().toUpperCase() == 'BODY')) {
        body = _str(c['text']) ?? '';
        break;
      }
    }
  }
  body = body.replaceAll('{{1}}', '{name}');

  // 'order_update' → 'Order update' for the picker's bold row title.
  final pretty = rawName.replaceAll('_', ' ');
  final displayName = pretty[0].toUpperCase() + pretty.substring(1);

  return WhatsappTemplate(
    id: pk.toString(),
    name: displayName,
    body: body.isEmpty ? displayName : body,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Remote data source
// ─────────────────────────────────────────────────────────────────────────────

class _ConversationMeta {
  const _ConversationMeta({required this.accountId, required this.phone});

  final Object? accountId; // whatsapp_account int pk
  final String phone; // wa_contact_phone (E.164, no '+')
}

class _TemplateMeta {
  const _TemplateMeta({required this.name, required this.language});

  final String name; // the send key (exact server name, not prettified)
  final String language;
}

/// HTTP + mapping for the WhatsApp slice. Conversation pks are INTs — entity
/// ids are their string form. Send endpoints need the account id + contact
/// phone, which never reach the UI entity, so they are cached here per
/// conversation (refetched from the detail endpoint when missing).
class MessagesRemoteDataSource {
  MessagesRemoteDataSource(this._api);

  final ApiService _api;

  final Map<String, _ConversationMeta> _conversationMeta = {};
  final Map<String, _TemplateMeta> _templateMeta = {};

  static const int _pageSize = ApiConfig.defaultPageSize;
  static const int _maxPages = 50; // safety cap; loop still breaks when next == null

  // ── Conversations ──

  Future<List<Map<String, dynamic>>> fetchConversationRows() async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; page <= _maxPages; page++) {
      final body = await _api.get(ApiEndpoints.whatsappConversations, query: {
        'page_size': _pageSize,
        if (page > 1) 'page': page,
      });
      final parsed = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      rows.addAll(parsed.results);
      if (parsed.next == null) break;
    }
    return rows;
  }

  List<Conversation> mapConversationRows(List rows, {DateTime? now}) {
    final out = <Conversation>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final conversation = conversationFromJson(map, now: now);
      if (conversation == null) continue;
      _rememberMeta(conversation.id, map);
      out.add(conversation);
    }
    return out;
  }

  void _rememberMeta(String id, Map<String, dynamic> row) {
    final phone = _str(row['wa_contact_phone']);
    if (phone == null && row['whatsapp_account'] == null) return;
    _conversationMeta[id] = _ConversationMeta(
      accountId: row['whatsapp_account'],
      phone: (phone ?? '').replaceFirst('+', ''),
    );
  }

  Future<_ConversationMeta?> _metaFor(String conversationId) async {
    final cached = _conversationMeta[conversationId];
    if (cached != null && cached.accountId != null && cached.phone.isNotEmpty) {
      return cached;
    }
    final body = await _api.get(ApiEndpoints.whatsappConversation(conversationId));
    if (body is Map<String, dynamic>) _rememberMeta(conversationId, body);
    return _conversationMeta[conversationId];
  }

  // ── Messages ──

  /// The latest page of the thread (server orders oldest-first, so that is the
  /// LAST page when the thread spans multiple pages).
  Future<List<Map<String, dynamic>>> fetchMessageRows(
      String conversationId) async {
    final path = ApiEndpoints.whatsappMessages(conversationId);
    final first = Paginated.fromAny<Map<String, dynamic>>(
        await _api.get(path, query: {'page_size': _pageSize}), (m) => m);
    if (first.next == null) return first.results;
    final lastPage = (first.count / _pageSize).ceil();
    final last = Paginated.fromAny<Map<String, dynamic>>(
        await _api.get(path, query: {'page_size': _pageSize, 'page': lastPage}),
        (m) => m);
    return last.results.isEmpty ? first.results : last.results;
  }

  List<ChatMessage> mapMessageRows(List rows) {
    final out = <ChatMessage>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final msg = chatMessageFromJson(Map<String, dynamic>.from(row));
      if (msg != null) out.add(msg);
    }
    return out;
  }

  /// One fetch, three views: the thread, the files in it and the links in it.
  /// Newest first on both derived tabs — the useful end of a long thread.
  ChatThread mapThreadRows(List rows) {
    final media = <ChatMedia>[];
    final links = <ChatLink>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final file = chatMediaFromJson(map);
      if (file != null) media.add(file);
      links.addAll(chatLinksFromJson(map));
    }
    return ChatThread(
      messages: mapMessageRows(rows),
      media: media.reversed.toList(),
      links: links.reversed.toList(),
    );
  }

  Future<void> markRead(String conversationId) =>
      _api.post(ApiEndpoints.whatsappConversationRead(conversationId));

  // ── Sends ──

  Future<ChatMessage?> sendText(String conversationId, String text) async {
    final meta = await _metaFor(conversationId);
    if (meta == null || meta.accountId == null || meta.phone.isEmpty) {
      return null;
    }
    await _api.post(ApiEndpoints.whatsappSendText, body: {
      'whatsapp_account_id': meta.accountId,
      'to': meta.phone,
      'body': text,
    });
    return ChatMessage(
        mine: true, text: text, time: _clockLabel(DateTime.now()), status: 'sent');
  }

  Future<ChatMessage?> sendTemplate(
      String conversationId, String templateId, String body) async {
    final meta = await _metaFor(conversationId);
    if (meta == null || meta.accountId == null || meta.phone.isEmpty) {
      return null;
    }
    final tpl = _templateMeta[templateId];
    await _api.post(ApiEndpoints.whatsappSendTemplate, body: {
      'whatsapp_account_id': meta.accountId,
      'to': meta.phone,
      // Fall back to the raw id: sends still work when the picker showed a
      // template the DS itself fetched under that name.
      'template_name': tpl?.name ?? templateId,
      'language_code': tpl?.language ?? 'en_US',
    });
    return ChatMessage(
        mine: true,
        text: body,
        time: _clockLabel(DateTime.now()),
        status: 'sent',
        tpl: true);
  }

  /// `POST /whatsapp/send/image/` (multipart). The window is checked
  /// server-side *before* the upload — a closed window still costs no
  /// bandwidth on the server's end, but the file leaves the device regardless.
  Future<ChatMessage?> sendImage(
    String conversationId,
    String path,
    String filename, {
    String caption = '',
  }) async {
    final meta = await _metaFor(conversationId);
    if (meta == null || meta.accountId == null || meta.phone.isEmpty) {
      return null;
    }
    final form = FormData.fromMap({
      'whatsapp_account_id': meta.accountId,
      'to': meta.phone,
      if (caption.isNotEmpty) 'caption': caption,
      'image': await MultipartFile.fromFile(path, filename: filename),
    });
    await _api.postForm(ApiEndpoints.whatsappSendImage, form);
    return ChatMessage(
        mine: true, text: filename, time: _clockLabel(DateTime.now()), status: 'sent');
  }

  /// `POST /whatsapp/send/document/` (multipart). `document` is a plain
  /// `FileField` server-side — any file type uploads, including audio/video
  /// (they arrive as a file attachment, not an inline player).
  Future<ChatMessage?> sendDocument(
    String conversationId,
    String path,
    String filename, {
    String caption = '',
  }) async {
    final meta = await _metaFor(conversationId);
    if (meta == null || meta.accountId == null || meta.phone.isEmpty) {
      return null;
    }
    final form = FormData.fromMap({
      'whatsapp_account_id': meta.accountId,
      'to': meta.phone,
      'filename': filename,
      if (caption.isNotEmpty) 'caption': caption,
      'document': await MultipartFile.fromFile(path, filename: filename),
    });
    await _api.postForm(ApiEndpoints.whatsappSendDocument, form);
    return ChatMessage(
        mine: true, text: filename, time: _clockLabel(DateTime.now()), status: 'sent');
  }

  /// `GET /whatsapp/media/<media_id>/` (whatsapp.md §5). 404 means no message
  /// in this org carries that id; 502 means Meta refused the fetch (usually
  /// media older than 30 days, which Meta purges) — both surface as [AppError]
  /// through the normal request path, not a special case here.
  Future<(List<int> bytes, String? contentType)> fetchMediaBytes(String mediaId) =>
      _api.getBytes(ApiEndpoints.whatsappMedia(mediaId));

  // ── Templates ──

  Future<List<Map<String, dynamic>>> fetchTemplateRows() async {
    final body = await _api.get(ApiEndpoints.whatsappTemplates, query: {
      'status': 'APPROVED',
      'page_size': _pageSize,
    });
    return Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
  }

  List<WhatsappTemplate> mapTemplateRows(List rows) {
    final out = <WhatsappTemplate>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final tpl = whatsappTemplateFromJson(map);
      if (tpl == null) continue;
      _templateMeta[tpl.id] = _TemplateMeta(
        name: _str(map['name']) ?? tpl.name,
        language: _str(map['language']) ?? 'en_US',
      );
      out.add(tpl);
    }
    return out;
  }
}
