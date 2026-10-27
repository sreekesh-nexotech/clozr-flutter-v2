import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/helpdesk/application/ticket_form_rules.dart';
import 'package:clozrapp/features/helpdesk/infrastructure/data_sources/remote/tickets_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

const _bug = CatalogOption(id: 't-bug', name: 'Bug', defaultPriority: 'High');
const _inquiry = CatalogOption(id: 't-inq', name: 'Inquiry', defaultPriority: 'Low');
const _plain = CatalogOption(id: 't-plain', name: 'Other');
const _types = [_bug, _inquiry, _plain];

const _uuid = '6a21decb-98e2-4510-ac7e-9d5128fc8340';

void main() {
  group('validateTicketInput (webapp validateIssueInput)', () {
    test('subject and customer are both reported', () {
      expect(
        validateTicketInput(
            subject: ' ', customerId: null, reportedFor: kReportedForClient, billable: false, hasAmount: false, hasBillableProduct: false),
        [kTicketSubjectRequired, kTicketCustomerRequired],
      );
    });
    test('an internal ticket needs no customer', () {
      expect(
        validateTicketInput(
            subject: 'x', customerId: null, reportedFor: kReportedForInternal, billable: false, hasAmount: false, hasBillableProduct: false),
        isEmpty,
      );
    });
    test('billable needs an amount or a product', () {
      List<String> v({bool amount = false, bool product = false}) => validateTicketInput(
          subject: 'x', customerId: _uuid, reportedFor: kReportedForClient, billable: true, hasAmount: amount, hasBillableProduct: product);
      expect(v(), [kBillableNeedsBasis]);
      expect(v(amount: true), isEmpty);
      expect(v(product: true), isEmpty);
    });
  });

  group('category default priority (UAT D19)', () {
    test('follows the category until the user picks', () {
      expect(priorityAfterCategoryChange(types: _types, typeId: 't-inq', current: 'Medium', pickedByUser: false), 'Low');
      expect(priorityAfterCategoryChange(types: _types, typeId: 't-bug', current: 'Low', pickedByUser: false), 'High');
      // No default → the model default.
      expect(priorityAfterCategoryChange(types: _types, typeId: 't-plain', current: 'High', pickedByUser: false), 'Medium');
      expect(priorityAfterCategoryChange(types: _types, typeId: null, current: 'High', pickedByUser: false), 'Medium');
      // A picked priority always wins.
      expect(priorityAfterCategoryChange(types: _types, typeId: 't-inq', current: 'Critical', pickedByUser: true), 'Critical');
    });
    test('hint names the category only while it applies', () {
      expect(priorityHint(types: _types, typeId: 't-inq', priority: 'Low', pickedByUser: false), 'Default for Inquiry');
      expect(priorityHint(types: _types, typeId: 't-inq', priority: 'Low', pickedByUser: true), isNull);
      expect(priorityHint(types: _types, typeId: 't-plain', priority: 'Medium', pickedByUser: false), isNull);
    });
  });

  group('customer picker copy (UAT D02)', () {
    test('notices', () {
      expect(customerPickerNotice(loading: true, forbidden: false, failed: false), 'Loading customers…');
      expect(customerPickerNotice(loading: true, forbidden: false, failed: false, query: 'ro'), 'Searching customers…');
      expect(customerPickerNotice(loading: false, forbidden: true, failed: true), "You don't have permission to view customers.");
      expect(customerPickerNotice(loading: false, forbidden: false, failed: false), isNull);
    });
    test('no match and footer', () {
      expect(customerNoMatchText(' zz '), 'No customers match “zz”');
      expect(customerNoMatchText(''), 'No customers found');
      expect(customerResultsFooter(20, 20, ''), isNull);
      expect(customerResultsFooter(20, 154, ''), 'Showing 20 of 154 customers — type to search them all.');
      expect(customerResultsFooter(20, 40, 'ro'), 'Showing 20 of 40 matches — keep typing to narrow them down.');
    });
    test('helper under the field', () {
      expect(customerFieldHelper(forbidden: false, internal: false), isNull);
      expect(customerFieldHelper(forbidden: false, internal: true), 'Optional for internal tickets.');
      expect(customerFieldHelper(forbidden: true, internal: false),
          "You don't have permission to view customers — ask your admin, or raise this as an internal ticket.");
    });
  });

  group('SLA box (UAT UX4)', () {
    final now = DateTime(2026, 10, 26, 21, 5);
    test('new ticket previews Resolve by from the customer SLA', () {
      final p = slaPreviewCopy(
          isEditing: false, customerId: _uuid, internal: false, customerSla: (value: 1, unit: 'hours'), now: now);
      expect(p.headline, 'Resolve by Mon 26 Oct, 22:05');
      expect(p.detail, '1 hour customer SLA, counted from when the ticket is created. Not editable per ticket.');
      final d = slaPreviewCopy(
          isEditing: false, customerId: _uuid, internal: false, customerSla: (value: 2, unit: 'days'), now: now);
      expect(d.headline, 'Resolve by Wed 28 Oct, 21:05');
      expect(d.detail.startsWith('2 days customer SLA'), isTrue);
    });
    test('no customer / unknown SLA', () {
      expect(slaPreviewCopy(isEditing: false, customerId: null, internal: true, customerSla: null, now: now).detail,
          'No SLA applies — an internal ticket without a customer has no deadline.');
      expect(slaPreviewCopy(isEditing: false, customerId: null, internal: false, customerSla: null, now: now).detail,
          kSlaFollowsCustomer);
      expect(slaPreviewCopy(isEditing: false, customerId: _uuid, internal: false, customerSla: null, now: now).headline, isNull);
    });
    test('editing states the recalculation rule', () {
      SlaPreview e({String? cust = _uuid, bool changed = true, bool resolved = false, CustomerSla? sla}) => slaPreviewCopy(
          isEditing: true, customerId: cust, internal: false, customerSla: sla, now: now, customerChanged: changed, resolved: resolved);
      expect(e(changed: false).detail, kSlaFollowsCustomer);
      expect(e(sla: (value: 2, unit: 'days')).headline, 'SLA recalculated on save');
      expect(e(sla: (value: 2, unit: 'days')).detail, '2 days from this customer, counted from when the ticket was opened.');
      expect(e(cust: null).detail, 'Saving without a customer removes the SLA — the ticket will have no deadline.');
      expect(e(resolved: true).detail, 'A resolved ticket keeps the SLA it was resolved under.');
    });
    test('customerSlaFrom keeps only usable terms', () {
      expect(customerSlaFrom({'sla_value': 7, 'sla_unit': 'days'}), (value: 7, unit: 'days'));
      expect(customerSlaFrom({'sla_value': '1', 'sla_unit': 'Hours'}), (value: 1, unit: 'hours'));
      expect(customerSlaFrom({'sla_value': null, 'sla_unit': 'days'}), isNull);
      expect(customerSlaFrom({'sla_value': 3}), isNull);
    });
  });

  group('billing copy', () {
    test('label and hint follow the GST basis', () {
      expect(billableAmountLabel(null), 'Billable amount (₹)');
      const excl = (inclusive: false, defaultSac: null, defaultGstRatePct: null);
      expect(billableAmountLabel(excl), 'Billable amount (₹, excl. GST)');
      expect(billableAmountHint(excl, hasProduct: true), 'An amount, a product, or both. GST is added on top of this amount.');
      expect(billableAmountHint(excl, hasProduct: false), contains('No default SAC for ticket charges yet'));
      expect(ticketBillingDefaultsFrom({'amounts_are': 'EXCLUSIVE', 'default_sac': null}), excl);
    });
    test('the server billing refusal is recognised', () {
      expect(isBillableBasisRefusal(fieldErrors: {'billable': ['x']}, message: 'x'), isTrue);
      expect(isBillableBasisRefusal(message: 'A billable ticket requires billable_amount or billable_product.'), isTrue);
      expect(isBillableBasisRefusal(message: 'assignee_no_module_access'), isFalse);
    });
  });

  group('writePayload — the form\'s keys', () {
    test('sends reported_for, contact, assignee and explicit clears', () {
      final out = TicketsRemoteDataSource.writePayload({
        'subject': 'S',
        'reported_for': 'self',
        'customer_id': null,
        'contact_id': null,
        'issue_type': null,
        'assigned_to': _uuid,
        'channel': 'whatsapp',
      });
      expect(out['reported_for'], 'self');
      expect(out.containsKey('customer_id') && out['customer_id'] == null, isTrue);
      expect(out.containsKey('contact_id') && out['contact_id'] == null, isTrue);
      expect(out.containsKey('issue_type') && out['issue_type'] == null, isTrue);
      expect(out['assigned_to'], _uuid);
      expect(out['channel'], 'whatsapp');
    });
    test('absent keys stay absent; junk values are dropped', () {
      final out = TicketsRemoteDataSource.writePayload({'subject': 'S', 'assigned_to': 'me', 'reported_for': 'boss'});
      expect(out.containsKey('assigned_to'), isFalse);
      expect(out.containsKey('reported_for'), isFalse);
      expect(out.containsKey('customer_id'), isFalse);
    });
  });
}
