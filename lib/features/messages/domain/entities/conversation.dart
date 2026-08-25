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

  bool get failed => status == 'failed';

  ChatMessage copyWith({String? status}) => ChatMessage(
        mine: mine,
        text: text,
        time: time,
        status: status ?? this.status,
        tpl: tpl,
        localId: localId,
      );

  @override
  List<Object?> get props => [mine, text, time, status, tpl, localId];
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
  });

  /// An explicit icon, as the prototype seed carries. Null on API rows — the
  /// pane resolves one from [kind] instead, which keeps the icon set (and its
  /// package) out of the data source.
  final IconData? icon;

  /// `image` | `video` | `audio` | `pdf` | `sheet` | `doc` | `file`.
  final String kind;
  final String name;
  final String meta;

  @override
  List<Object?> get props => [name, meta, kind];
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
