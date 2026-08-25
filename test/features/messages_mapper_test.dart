import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:clozrapp/features/messages/infrastructure/data_sources/remote/messages_remote_ds.dart';

void main() {
  final now = DateTime(2026, 8, 4, 10, 0);

  group('conversationFromJson', () {
    test('maps a full row — INT pk stringified, contact fields, window label', () {
      final lastAt = now.subtract(const Duration(minutes: 27));
      final row = <String, dynamic>{
        'id': 42,
        'whatsapp_account': 3,
        'wa_contact_phone': '919812345678',
        'wa_contact_name': 'Ramesh Pillai',
        'lead': 'b7f3c9a1-8f2e-4f6d-9a3b-1c2d3e4f5a6b',
        'lead_name': 'Kalyan Silks',
        'contact_name': null,
        'unread_count': 3,
        'is_window_open': true,
        'window_expires_at':
            now.add(const Duration(hours: 14, minutes: 22)).toIso8601String(),
        'last_message_at': lastAt.toIso8601String(),
        'last_message_preview': 'You: Sending the quote PDF now.',
      };

      final c = conversationFromJson(row, now: now)!;
      expect(c.id, '42'); // int pk → string id
      expect(c.leadId, 'b7f3c9a1-8f2e-4f6d-9a3b-1c2d3e4f5a6b');
      expect(c.name, 'Ramesh Pillai');
      expect(c.company, 'Kalyan Silks');
      expect(c.initials, 'RP');
      expect(c.online, false);
      expect(c.unread, 3);
      expect(c.windowLeft, '14h 22m left');
      expect(c.windowOpen, true);
      expect(c.lastTime, '27m ago');
      // The row's preview becomes a single synthetic thread message.
      expect(c.messages, hasLength(1));
      expect(c.messages.single.mine, false);
      expect(c.preview, 'You: Sending the quote PDF now.');
      expect(c.media, isEmpty);
      expect(c.links, isEmpty);
    });

    test('closed window → null windowLeft; defensive fallbacks on nulls', () {
      final c = conversationFromJson(<String, dynamic>{
        'id': 7,
        'is_window_open': false,
        'window_expires_at': null,
      }, now: now)!;
      expect(c.id, '7');
      expect(c.windowLeft, isNull);
      expect(c.windowOpen, false);
      expect(c.name, 'Unknown');
      expect(c.company, '');
      expect(c.unread, 0);
      expect(c.messages, isEmpty);
      expect(c.preview, 'No messages yet');
    });

    test('window edge cases', () {
      // No window fields at all → keep the composer usable.
      expect(windowLeftFromJson(<String, dynamic>{}, now: now), '24h');
      // Open flag but no expiry → trust the flag.
      expect(
        windowLeftFromJson(<String, dynamic>{
          'is_window_open': true,
          'window_expires_at': null,
        }, now: now),
        '24h',
      );
      // Expiry in the past without an open flag → closed.
      expect(
        windowLeftFromJson(<String, dynamic>{
          'window_expires_at':
              now.subtract(const Duration(hours: 1)).toIso8601String(),
        }, now: now),
        isNull,
      );
      // Sub-hour remainder drops the hour part.
      expect(
        windowLeftFromJson(<String, dynamic>{
          'is_window_open': true,
          'window_expires_at':
              now.add(const Duration(minutes: 40)).toIso8601String(),
        }, now: now),
        '40m left',
      );
    });

    test('row without a pk is skipped', () {
      expect(conversationFromJson(<String, dynamic>{}), isNull);
    });
  });

  group('chatMessageFromJson', () {
    final ts = DateTime(2026, 8, 4, 9, 58);
    final clock = DateFormat('h:mm a').format(ts); // '9:58 AM'

    test('outbound read message', () {
      final m = chatMessageFromJson(<String, dynamic>{
        'direction': 'outbound',
        'message_type': 'text',
        'body': 'Sharing the revised estimate.',
        'status': 'read',
        'timestamp': ts.toIso8601String(),
      })!;
      expect(m.mine, true);
      expect(m.text, 'Sharing the revised estimate.');
      expect(m.time, clock);
      expect(m.status, 'read');
      expect(m.tpl, false);
    });

    test('delivered maps to sent; inbound never carries a status', () {
      final sent = chatMessageFromJson(<String, dynamic>{
        'direction': 'outbound',
        'body': 'On it.',
        'status': 'delivered',
      })!;
      expect(sent.status, 'sent');

      final inbound = chatMessageFromJson(<String, dynamic>{
        'direction': 'inbound',
        'body': 'Thanks!',
        'status': 'read',
      })!;
      expect(inbound.mine, false);
      expect(inbound.status, '');
    });

    test('template rows flag tpl; media rows fall back to a type label', () {
      final tpl = chatMessageFromJson(<String, dynamic>{
        'direction': 'outbound',
        'message_type': 'template',
        'template_name': 'quote_shared',
        'body': 'Hi Asha, we have shared the quote.',
      })!;
      expect(tpl.tpl, true);

      final media = chatMessageFromJson(<String, dynamic>{
        'direction': 'inbound',
        'message_type': 'image',
        'body': null,
      })!;
      expect(media.text, '[image]');
    });

    test('is_from_me alias and malformed rows', () {
      final m = chatMessageFromJson(<String, dynamic>{
        'is_from_me': true,
        'body': 'hello',
      })!;
      expect(m.mine, true);
      expect(chatMessageFromJson(<String, dynamic>{}), isNull);
    });
  });

  group('whatsappTemplateFromJson', () {
    test('maps pk, prettified name and BODY text with {{1}} → {name}', () {
      final t = whatsappTemplateFromJson(<String, dynamic>{
        'id': 7,
        'template_id': '1234567890',
        'name': 'quote_shared',
        'language': 'en_US',
        'status': 'APPROVED',
        'components': [
          {'type': 'HEADER', 'text': 'Quote'},
          {'type': 'BODY', 'text': 'Hi {{1}}, your quote is ready.'},
        ],
      })!;
      expect(t.id, '7');
      expect(t.name, 'Quote shared');
      expect(t.body, 'Hi {name}, your quote is ready.');
      expect(t.resolve('Asha'), 'Hi Asha, your quote is ready.');
    });

    test('missing components fall back to the name; missing name skips', () {
      final t = whatsappTemplateFromJson(<String, dynamic>{
        'id': 9,
        'name': 'site_visit',
      })!;
      expect(t.body, 'Site visit');
      expect(whatsappTemplateFromJson(<String, dynamic>{'id': 1}), isNull);
    });
  });

  // The Medias and Links tabs were filled only by the prototype seed, so in API
  // mode they reported "nothing shared" whatever the thread contained. Both are
  // now read off the same message rows — field names verified against the dev
  // backend (`media_url`, `media_mime_type`, `message_type`).
  group('chatMediaFromJson', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
          'id': 1,
          'direction': 'inbound',
          'timestamp': now.subtract(const Duration(hours: 2)).toIso8601String(),
          ...extra,
        };

    test('a text message carries no file', () {
      expect(
          chatMediaFromJson(row({'message_type': 'text', 'body': 'Hi', 'media_url': ''})),
          isNull);
      // The live rows send empty strings rather than null for a text message.
      expect(chatMediaFromJson(row({'message_type': 'text'})), isNull);
    });

    test('a document takes its name from the URL and its kind from the mime', () {
      final m = chatMediaFromJson(row({
        'message_type': 'document',
        'media_url': 'https://cdn.example.com/media/fit-out-quote-v2.pdf?token=abc',
        'media_mime_type': 'application/pdf',
      }), now: now)!;

      expect(m.name, 'fit-out-quote-v2.pdf'); // query string dropped
      expect(m.meta, startsWith('PDF · '));
      expect(m.kind, 'pdf');
      // The icon set stays in the presentation layer.
      expect(m.icon, isNull);
    });

    test('a caption wins over the file name', () {
      final m = chatMediaFromJson(row({
        'message_type': 'image',
        'media_url': 'https://cdn.example.com/media/IMG_0042.jpg',
        'media_mime_type': 'image/jpeg',
        'caption': 'Site photo — east wall',
      }), now: now)!;

      expect(m.name, 'Site photo — east wall');
      expect(m.meta, startsWith('JPEG · '));
    });

    test('a URL with no extension still names something usable', () {
      final m = chatMediaFromJson(row({
        'message_type': 'audio',
        'media_url': 'https://cdn.example.com/media/',
      }), now: now)!;

      expect(m.name, 'Audio');
    });
  });

  group('chatLinksFromJson', () {
    test('pulls every URL out of a body, http or bare www', () {
      final links = chatLinksFromJson({
        'body': 'See https://kairali.in/work/showrooms and www.example.com/pricing',
        'timestamp': now.subtract(const Duration(days: 2)).toIso8601String(),
      }, now: now);

      expect(links, hasLength(2));
      expect(links[0].url, 'https://kairali.in/work/showrooms');
      expect(links[0].title, 'kairali.in/work'); // host + first segment
      expect(links[1].url, 'www.example.com/pricing');
      expect(links[0].meta, isNotEmpty);
    });

    test('sentence punctuation is not part of the address', () {
      final links = chatLinksFromJson({'body': 'Here: https://acme.test/quote.'});

      expect(links.single.url, 'https://acme.test/quote');
    });

    test('a body with no URL yields nothing', () {
      expect(chatLinksFromJson({'body': 'Sending the quote now'}), isEmpty);
      expect(chatLinksFromJson({'body': null}), isEmpty);
    });
  });
}
