import 'package:clozrapp/features/notifications/application/notification_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? leadName(String type, String text) => switch (notificationLinkFor(type, text)) {
        LeadByName(:final name) => name,
        _ => null,
      };

  test('lead events name the lead (quoted or after "lead:")', () {
    expect(leadName('LeadAssigned', 'You have been assigned to lead: UAT E2E Seven'), 'UAT E2E Seven');
    expect(leadName('LeadNoteAdded', 'New note "Note" added to lead "UAT E2E Seven".'), 'UAT E2E Seven');
    expect(leadName('LeadStatusChanged', 'Lead "Manoj Nair" status changed to Won.'), 'Manoj Nair');
    expect(leadName('LeadConverted', 'Lead "uat conv lead" has been converted to a customer.'), 'uat conv lead');
  });

  test('quote events give the quote number, revisions included', () {
    final l = notificationLinkFor('QuoteDiscountApprovalDecided', 'Discount on quote QTN-00037 was approved.');
    expect(l, isA<QuoteByNumber>().having((q) => q.number, 'number', 'QTN-00037'));
    final r = notificationLinkFor('QuotationExpiryReminder', 'QTN-00038-R2 expires in 3 days.');
    expect(r, isA<QuoteByNumber>().having((q) => q.number, 'number', 'QTN-00038-R2'));
  });

  test('a mention quotes the note; other types give nothing', () {
    final m = notificationLinkFor('NoteMention', 'Ashish Nexotech mentioned you: @Neeraja Pradeep please check');
    expect(m, isA<NoteByContent>().having((n) => n.content, 'content', '@Neeraja Pradeep please check'));
    expect(notificationLinkFor('TaskAssigned', 'You have been assigned to task: "x".'), isNull);
    expect(notificationLinkFor('LeadAssigned', 'Something else'), isNull);
  });

  test('note source and loose content match', () {
    expect(noteSourceOf({'source': {'kind': 'lead', 'id': 'u1'}}), ('lead', 'u1'));
    expect(noteSourceOf({'source': null}), isNull);
    expect(noteMatchesMention('<p>@Neeraja Pradeep  please check</p>', '@Neeraja Pradeep please check'), isTrue);
    expect(noteMatchesMention('another note', '@Neeraja Pradeep please check'), isFalse);
  });
}
