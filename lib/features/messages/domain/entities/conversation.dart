import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

/// A single chat message inside a conversation thread.
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.mine,
    required this.text,
    required this.time,
    this.status = '',
    this.tpl = false,
    this.localId,
    this.attachmentPath,
    this.attachmentKind,
    this.mediaId,
  });

  final bool mine; // true = sent by me (right, blue bubble)
  final String text;
  final String time;
  final String status; // 'read' | 'sent' | 'failed' | '' (only meaningful when mine)
  final bool tpl; // approved WhatsApp template message

  /// Client-side id for optimistic outgoing bubbles, so the send result can be
  /// reconciled back onto the exact bubble (mark sent/failed, retry). Null for
  /// fetched/incoming messages.
  final String? localId;

  /// The local device path a picked attachment was uploaded from. Only ever
  /// set on an optimistic outgoing bubble — never populated from a fetched
  /// row — so [retryMessage] knows to re-upload rather than re-send text, and
  /// so tapping a just-sent bubble can open the file straight off the device
  /// without a round trip (`whatsapp.md` §5: "the optimistic bubble should
  /// render the local File object URL").
  final String? attachmentPath;

  /// 'image' | 'document', paired with [attachmentPath]. Null for a plain
  /// text/template message.
  final String? attachmentKind;

  /// WhatsApp's media id, present on an image/document row once it comes back
  /// from the server (both directions — an outbound row never carries
  /// `media_url`, only this). Used to open the file through the authenticated
  /// media proxy (`GET /whatsapp/media/<id>/`) once [attachmentPath]'s local
  /// file is no longer available (a later session, a cleared cache).
  final String? mediaId;

  bool get failed => status == 'failed';
  bool get isAttachment => attachmentPath != null || mediaId != null;

  ChatMessage copyWith({String? status}) => ChatMessage(
        mine: mine,
        text: text,
        time: time,
        status: status ?? this.status,
        tpl: tpl,
        localId: localId,
        attachmentPath: attachmentPath,
        attachmentKind: attachmentKind,
        mediaId: mediaId,
      );

  @override
  List<Object?> get props =>
      [mine, text, time, status, tpl, localId, attachmentPath, attachmentKind, mediaId];
}

/// One conversation's thread as the API serves it: the messages, plus the two
/// derived views the chat screen's other tabs render.
///
/// Media and links are not separate endpoints — they are the same message rows
/// read differently (a row with a `media_url`, a URL inside a body), so they
/// come back from the one fetch rather than costing two more.
class ChatThread {
  const ChatThread({
    this.messages = const [],
    this.media = const [],
    this.links = const [],
  });

  final List<ChatMessage> messages;
  final List<ChatMedia> media;
  final List<ChatLink> links;
}

/// A shared file in the conversation's "Medias" tab.
class ChatMedia extends Equatable {
  const ChatMedia({
    this.icon,
    this.kind = 'file',
    required this.name,
    required this.meta,
    this.mediaId,
  });

  /// An explicit icon, as the prototype seed carries. Null on API rows — the
  /// pane resolves one from [kind] instead, which keeps the icon set (and its
  /// package) out of the data source.
  final IconData? icon;

  /// `image` | `video` | `audio` | `pdf` | `sheet` | `doc` | `file`.
  final String kind;
  final String name;
  final String meta;

  /// WhatsApp's media id for this row, when the API supplied one — the same
  /// field [ChatMessage.mediaId] carries. Used to fetch the file through the
  /// authenticated media proxy when the row's `media_url` is empty (the
  /// common case: WhatsApp inbound rows arrive with only an id). Null on the
  /// prototype seed, so its rows have nothing to download.
  final String? mediaId;

  @override
  List<Object?> get props => [name, meta, kind, mediaId];
}

/// A shared link in the conversation's "Links" tab.
class ChatLink extends Equatable {
  const ChatLink({required this.title, required this.url, required this.meta});

  final String title;
  final String url;
  final String meta;

  @override
  List<Object?> get props => [title, url, meta];
}

/// A WhatsApp-style conversation with a lead. `windowLeft == null` means the
/// 24-hour free-form window has closed (only templates may be sent).
class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.leadId,
    required this.name,
    required this.company,
    required this.initials,
    required this.online,
    required this.unread,
    required this.windowLeft,
    required this.lastTime,
    required this.messages,
    this.phone = '',
    this.media = const [],
    this.links = const [],
  });

  final String id;
  final String? leadId;
  final String name;
  final String company;
  final String initials;
  final bool online;
  final int unread;
  final String? windowLeft; // e.g. "20h 58m left"; null => window closed
  final String lastTime;

  /// The contact's WhatsApp number as digits only (`wa_contact_phone` with the
  /// `+` and any separators removed). Kept on the entity because it is the only
  /// reliable way to tie a conversation to a CRM record the API did not link:
  /// `lead` is null on every conversation that arrived before the number was
  /// matched to a lead, and WhatsApp itself is addressed by number, not by id.
  final String phone;
  final List<ChatMessage> messages;
  final List<ChatMedia> media;
  final List<ChatLink> links;

  bool get windowOpen => windowLeft != null;
  bool get hasUnread => unread > 0;

  /// Last-message preview for the conversation list.
  String get preview {
    if (messages.isEmpty) return 'No messages yet';
    final last = messages.last;
    return '${last.mine ? 'You: ' : ''}${last.text}';
  }

  Conversation copyWith({
    int? unread,
    String? windowLeft,
    String? lastTime,
    List<ChatMessage>? messages,
    List<ChatMedia>? media,
    List<ChatLink>? links,
  }) {
    return Conversation(
      id: id,
      leadId: leadId,
      phone: phone,
      name: name,
      company: company,
      initials: initials,
      online: online,
      unread: unread ?? this.unread,
      windowLeft: windowLeft ?? this.windowLeft,
      lastTime: lastTime ?? this.lastTime,
      messages: messages ?? this.messages,
      media: media ?? this.media,
      links: links ?? this.links,
    );
  }

  @override
  List<Object?> get props => [id, unread, lastTime, messages, windowLeft];
}

/// A phone number reduced to what WhatsApp addresses it by: digits only, no
/// `+`, no spaces or brackets. CRM numbers are typed by hand ("+91 98470
/// 00000") while `wa_contact_phone` is bare E.164, so nothing can be compared
/// until both sides have been through this.
String waDigits(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

/// Whether two numbers are the same WhatsApp contact.
///
/// Compared as a suffix rather than for equality: the same person is stored as
/// `+91 98470 00000` in the CRM, `919847000000` by WhatsApp, and sometimes as a
/// bare local number by whoever typed the lead in. A country code that is
/// present on one side and missing on the other is the normal case, not the
/// exception, so an equality test would miss nearly every match. Numbers
/// shorter than 8 digits (extensions, half-filled fields) never match — a short
/// suffix would collide across unrelated contacts.
bool sameWaNumber(String a, String b) {
  final x = waDigits(a);
  final y = waDigits(b);
  if (x.length < 8 || y.length < 8) return false;
  return x.length <= y.length ? y.endsWith(x) : x.endsWith(y);
}
