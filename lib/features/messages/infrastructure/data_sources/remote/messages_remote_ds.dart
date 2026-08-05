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
    leadId: _str(row['lead']),
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
  );
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
