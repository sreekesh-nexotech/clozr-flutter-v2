// Where the lead's WhatsApp button lands. Two routes, because the CRM cannot
// create a WhatsApp conversation on demand (`/api/v1/whatsapp/` has no such
// endpoint): the in-app thread when one already exists, the WhatsApp app
// otherwise. Matching a lead to its thread is the whole game — the `lead` link
// is only set once the backend has matched the number, so the number itself has
// to be a fallback key.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/providers/lead_whatsapp_providers.dart';
import 'package:clozrapp/features/messages/application/providers/messages_providers.dart';
import 'package:clozrapp/features/messages/domain/entities/conversation.dart';
import 'package:clozrapp/features/messages/infrastructure/data_sources/remote/messages_remote_ds.dart';

Conversation _conv({
  required String id,
  String? leadId,
  String phone = '',
}) =>
    Conversation(
      id: id,
      leadId: leadId,
      phone: phone,
      name: 'Contact $id',
      company: '',
      initials: 'C',
      online: false,
      unread: 0,
      windowLeft: '3h left',
      lastTime: 'now',
      messages: const [],
    );

/// Builds a service over a fixed conversation list, recording what it launched.
({LeadWhatsappService service, List<Uri> launched}) _service(
  List<Conversation> conversations, {
  bool launchSucceeds = true,
  bool lookupThrows = false,
}) {
  final launched = <Uri>[];
  return (
    service: LeadWhatsappService(
      ensureLoaded: () async {
        if (lookupThrows) throw Exception('offline');
      },
      conversations: () => conversations,
      launcher: (uri) async {
        launched.add(uri);
        return launchSucceeds;
      },
    ),
    launched: launched,
  );
}

void main() {
  group('findConversationForLead', () {
    test('the lead link wins when the API has set it', () {
      final rows = [
        _conv(id: '1', phone: '919999000011'),
        _conv(id: '2', leadId: 'L7', phone: '918888000022'),
      ];
      final found = findConversationForLead(rows, leadId: 'L7', phone: '');
      expect(found?.id, '2');
    });

    test('an unlinked thread is still found by number', () {
      // The common case: the customer messaged in before the lead was matched,
      // so `lead` is null and only wa_contact_phone ties the two together.
      final rows = [_conv(id: '9', phone: '919847000000')];
      final found =
          findConversationForLead(rows, leadId: 'L7', phone: '+91 98470 00000');
      expect(found?.id, '9');
    });

    test('a country code on one side only still matches', () {
      final rows = [_conv(id: '9', phone: '919847000000')];
      expect(findConversationForLead(rows, leadId: 'L7', phone: '9847000000')?.id, '9');
    });

    test('a different number does not match', () {
      final rows = [_conv(id: '9', phone: '919847000000')];
      expect(findConversationForLead(rows, leadId: 'L7', phone: '919847000001'), isNull);
    });

    test('a too-short number never matches — a short suffix collides', () {
      final rows = [_conv(id: '9', phone: '919847000000')];
      expect(findConversationForLead(rows, leadId: 'L7', phone: '0000'), isNull);
    });
  });

  group('LeadWhatsappService', () {
    test('an existing thread opens in the CRM, nothing is launched', () async {
      final t = _service([_conv(id: '42', leadId: 'L7', phone: '919847000000')]);
      final outcome = await t.service.open(leadId: 'L7', phone: '+91 98470 00000');

      expect(outcome.result, LeadWhatsappResult.openedThread);
      expect(outcome.conversationId, '42');
      expect(t.launched, isEmpty);
    });

    test('no thread hands the number to WhatsApp as bare E.164', () async {
      final t = _service([_conv(id: '1', leadId: 'L1', phone: '911111111111')]);
      final outcome = await t.service.open(leadId: 'L7', phone: '+91 98470 00000');

      expect(outcome.result, LeadWhatsappResult.handedToWhatsapp);
      expect(t.launched.single, Uri.parse('https://wa.me/919847000000'));
    });

    test('a lead with no number reports it rather than launching', () async {
      final t = _service(const []);
      final outcome = await t.service.open(leadId: 'L7', phone: '');

      expect(outcome.result, LeadWhatsappResult.noNumber);
      expect(t.launched, isEmpty);
    });

    test('a device that cannot open WhatsApp is reported', () async {
      final t = _service(const [], launchSucceeds: false);
      final outcome = await t.service.open(leadId: 'L7', phone: '919847000000');

      expect(outcome.result, LeadWhatsappResult.whatsappUnavailable);
    });

    test('a failed lookup still reaches the number, and says why', () async {
      // The list could not be fetched, so "no thread" is unproven — the number
      // is reachable either way, but the user is told the check failed.
      final t = _service(const [], lookupThrows: true);
      final outcome = await t.service.open(leadId: 'L7', phone: '919847000000');

      expect(outcome.result, LeadWhatsappResult.handedToWhatsapp);
      expect(outcome.message, isNotNull);
      expect(t.launched, isNotEmpty);
    });

    test('a failed lookup on a numberless lead is not reported as "no number"',
        () async {
      final t = _service(const [], lookupThrows: true);
      final outcome = await t.service.open(leadId: 'L7', phone: '');

      expect(outcome.result, LeadWhatsappResult.lookupFailed);
      expect(t.launched, isEmpty);
    });
  });

  group('conversationFromJson lead link', () {
    test('an integer lead pk maps to a matchable id', () {
      // It used to be read as a string only, so an int-keyed org lost the link
      // on every row.
      final c = conversationFromJson({
        'id': 5,
        'lead': 1234,
        'wa_contact_phone': '+919847000000',
        'wa_contact_name': 'Ramesh',
      });
      expect(c?.leadId, '1234');
      expect(c?.phone, '919847000000');
    });

    test('a nested lead object and a missing link both behave', () {
      final nested = conversationFromJson({
        'id': 6,
        'lead': {'id': 'abc-uuid'},
        'wa_contact_phone': '919847000001',
      });
      expect(nested?.leadId, 'abc-uuid');

      final none = conversationFromJson({'id': 7, 'wa_contact_phone': '919847000002'});
      expect(none?.leadId, isNull);
      expect(none?.phone, '919847000002');
    });
  });
}
