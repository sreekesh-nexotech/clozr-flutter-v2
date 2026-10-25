import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/crm/application/customer_detail_rules.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:clozrapp/features/crm/presentation/components/customer_detail/customer_accounting_panel.dart';
import 'package:flutter_test/flutter_test.dart';

ViewColumn col(String name, String type, int order, {String? label, List<(String, String)> choices = const []}) =>
    ViewColumn(name: name, label: label ?? name, order: order, type: type, inFields: type.isNotEmpty, choices: choices);

void main() {
  group('header', () {
    test('money, code, since, badges and lost reason', () {
      final facts = CustomerHeaderFacts.fromRow({
        'customer_id': '0c268520-62c7-4bcd-be16-cb9ce4a78369',
        'reference': 'CUST-0006',
        'organization_name': 'Kerala Agro',
        'status_entered_at': '2026-10-22T12:25:59.923360+05:30',
        'deal_value': '350000.00',
        'revenue_received': '11800.50',
        'status_type': 'lost',
        'lost_reason_name': 'Budget cut',
        'lost_reason_note': 'Q4 freeze',
        'linked_leads': [
          {'lead_id': 'a', 'is_converted': true, 'is_upsell': false},
          {'lead_id': 'b', 'is_converted': false, 'is_upsell': true},
        ],
      });
      expect(facts.subtitle, 'CUST-0006 · Kerala Agro');
      expect(facts.since, '22 Oct 2026');
      expect(webMoney(facts.dealValue), '₹3,50,000');
      expect(webMoney(facts.received), '₹11,800.50');
      expect(facts.isConverted, isTrue);
      expect(facts.isUpsell, isTrue);
      expect(facts.isLost, isTrue);
      expect(facts.lostReason, 'Budget cut — Q4 freeze');
    });

    test('value falls back to revenue; no reason recorded', () {
      final facts = CustomerHeaderFacts.fromRow({'customer_id': 'abcdef1234', 'revenue': 5000});
      expect(facts.code, '#abcdef12');
      expect(facts.dealValue, 5000);
      expect(facts.received, isNull);
      expect(describeLostReason(null, ''), 'No reason recorded');
    });
  });

  group('lost impact', () {
    final impact = CustomerLostImpact.fromJson({
      'open_instalments': [
        {'amount_expected': '86999.00', 'invoiced': false, 'quotation_number': 'Q-1', 'installment_number': 1},
        {'amount_expected': '1000.00', 'invoiced': true},
      ],
      'draft_invoices': [
        {'number': 'D-1', 'grand_total': '10'},
      ],
      'legacy_quotes': [
        {'quotation_number': 'QT-0001'},
        {'quotation_number': 'QT-0002'},
      ],
      'upsell_leads': [
        {'lead_name': 'Elsa upsell'},
      ],
      'money_received': {'amount': '11800', 'payment_count': 2, 'customer_credit': '500'},
    })!;

    test('summary lines match the webapp', () {
      expect(lostSummaryLines(impact), [
        '1 open instalment (₹86,999.00) and their follow-up tasks are cancelled',
        '1 draft invoice is voided',
        '2 other quotes of this customer are closed the same way: QT-0001, QT-0002',
        '1 open upsell lead moves to Lost with the same reason: Elsa upsell',
      ]);
    });

    test('money received note', () {
      expect(describeMoneyReceived(impact),
          '₹11,800.00 already received stays with the customer as credit (unapplied credit now ₹500.00). Nothing is refunded automatically.');
      expect(describeMoneyReceived(const CustomerLostImpact()), isNull);
      expect(describeMoneyReceived(const CustomerLostImpact(customerCredit: 0)), isNull);
    });

    test('409 cause → only customers with open invoices', () {
      final list = customerLostImpactsFromCause({
        'customers': [
          {'customer_id': 'a', 'open_invoices': [{'number': 'INV-1', 'amount_due': '100'}]},
          {'customer_id': 'b', 'open_invoices': []},
        ],
      });
      expect(list.map((i) => i.customerId), ['a']);
      expect(list.single.amountDue, 100);
      expect(describeOpenInvoices(1, 100), '1 invoice (₹100.00) is issued but unpaid — issuing credit notes will cancel it.');
    });
  });

  group('SLA', () {
    test('options', () {
      final values = slaOptions().map((o) => o.$1).toList();
      expect(values.where((v) => v.endsWith('|hours')).map((v) => v.split('|').first),
          ['1', '2', '3', '4', '6', '8', '12', '24', '48']);
      expect(values.where((v) => v.endsWith('|days')).map((v) => v.split('|').first),
          ['1', '2', '3', '5', '7', '14', '30', '60', '90']);
      expect(values.any((v) => v.endsWith('|minutes')), isFalse);
      final respond = slaOptions(withMinutes: true);
      expect(respond.take(5).map((o) => o.$2), ['5 minutes', '10 minutes', '15 minutes', '30 minutes', '45 minutes']);
      expect(slaOptions().first.$2, '1 hour');
    });

    test('rows, default and patches', () {
      final cols = [col('sla_value', 'integer', 16), col('first_response_value', 'integer', 18), col('sla_mode', 'string', 52)];
      final built = buildCustomerInfoFields(
        row: {'name': 'A', 'sla_value': null, 'sla_unit': null, 'first_response_value': null, 'first_response_unit': null, 'sla_mode': 'policy'},
        columns: cols,
        editable: true,
      );
      final resolve = built.info.firstWhere((f) => f.name == '__sla_resolve');
      expect(resolve.editValue, '7|days');
      expect(customerFieldPatch(resolve, '3|days'), {'sla_value': 3, 'sla_unit': 'days'});
      expect(customerFieldPatch(resolve, '12|hours'), {'sla_value': 12, 'sla_unit': 'hours'});
      final respond = built.info.firstWhere((f) => f.name == '__sla_respond');
      expect(respond.value, 'Not set');
      expect(respond.options.first, ('', 'Not set'));
      expect(customerFieldPatch(respond, '15|minutes'), {'first_response_value': 15, 'first_response_unit': 'minutes'});
      expect(customerFieldPatch(respond, ''), {'first_response_value': null, 'first_response_unit': null});
      final mode = built.info.firstWhere((f) => f.name == '__sla_mode');
      expect(mode.label, 'SLA source');
      expect(mode.value, 'Tenant SLA policy');
      expect(slaText(3, 'days', 'Resolve within'), 'Resolve within 3 days');
      expect(slaText(1, 'hours', 'Respond within'), 'Respond within 1 hour');
    });

    test('respond-by is hidden when unset and read-only', () {
      final built = buildCustomerInfoFields(
        row: {'first_response_value': null, 'first_response_unit': null},
        columns: [col('first_response_value', 'integer', 18)],
        editable: false,
      );
      expect(built.info.where((f) => f.name == '__sla_respond'), isEmpty);
    });
  });

  group('info fields', () {
    final row = {
      'name': 'Elsa Mary',
      'email': 'e@x.com',
      'revenue': '350000.00',
      'source': 'Social Media',
      'value_need': {'value': 1000, 'need': 'Panels'},
      'score': 10,
      'industry': null,
      'industry_name': null,
      'gstin': null,
      'is_vip': true,
      'custom_fields': {'renewal': '2026-12-01'},
    };
    final cols = [
      col('email', 'string', 3),
      col('source', '', 6),
      col('value_need', '', 7),
      col('revenue', 'decimal', 8),
      col('industry', 'foreignkey', 9),
      col('score', '', 13),
      col('is_vip', 'boolean', 14),
      const ViewColumn(name: 'custom_fields.renewal', label: 'Renewal', order: 15, type: 'date', isCustom: true),
      col('assignees', 'manytomany', 11),
    ];

    test('editable layout', () {
      final f = buildCustomerInfoFields(row: row, columns: cols, editable: true, industryOptions: [('i1', 'Solar')]).info;
      expect(f.first.name, 'name');
      expect(f.first.editable, isTrue);
      final revenue = f.firstWhere((x) => x.name == 'revenue');
      expect(revenue.value, '₹3,50,000');
      expect(customerFieldPatch(revenue, '400000'), {'revenue': 400000});
      expect(customerFieldPatch(revenue, ''), {'revenue': null});
      expect(f.firstWhere((x) => x.name == 'source').editable, isFalse);
      expect(f.firstWhere((x) => x.name == 'source').hint, sourceHint);
      expect(f.firstWhere((x) => x.name == 'value_need').value, '₹1,000 · Panels');
      expect(f.firstWhere((x) => x.name == 'score').value, '10 / 100');
      final industry = f.firstWhere((x) => x.name == 'industry');
      expect(industry.options.first, ('', 'No industry'));
      expect(customerFieldPatch(industry, ''), {'industry': null});
      final vip = f.firstWhere((x) => x.name == 'is_vip');
      expect(vip.kind, InfoEditKind.boolean);
      expect(customerFieldPatch(vip, 'false'), {'is_vip': false});
      final renewal = f.firstWhere((x) => x.name == 'custom_fields.renewal');
      expect(renewal.kind, InfoEditKind.date);
      expect(customerFieldPatch(renewal, '2027-01-01'), {
        'custom_fields': {'renewal': '2027-01-01'},
      });
      final gstin = f.firstWhere((x) => x.name == 'gstin');
      expect(gstin.placeholder, 'e.g. 32ABCDE1234F1Z5');
      expect(customerFieldPatch(gstin, ' 32abcde1234f1z5 '), {'gstin': '32ABCDE1234F1Z5'});
      expect(f.where((x) => x.name == 'assignees'), isEmpty);
      expect(customerFieldPatch(f.first, 'Elsa Mary'), isNull);
      expect(customerFieldInputError(revenue, '12abc'), isNotNull);
    });

    test('without update nothing is editable', () {
      final f = buildCustomerInfoFields(row: row, columns: cols, editable: false, industryOptions: [('i1', 'Solar')]).info;
      expect(f.where((x) => x.editable), isEmpty);
    });

    test('billing section when the org shows it', () {
      final b = buildCustomerInfoFields(
        row: {'billing_city': 'Kochi', 'gstin': '32AB'},
        columns: [col('billing_city', 'string', 57, label: 'Billing City'), col('gstin', 'string', 69, label: 'GSTIN')],
        editable: true,
      );
      expect(b.billing.map((x) => x.name), ['billing_city', 'gstin']);
      expect(b.info.where((x) => x.name == 'gstin'), isEmpty);
    });

    test('write errors read as the server sentence', () {
      const v = AppError(
        type: AppErrorType.validation,
        message: 'email: Enter a valid email address.',
        statusCode: 400,
        fieldErrors: {'email': ['Enter a valid email address.']},
      );
      expect(customerWriteError(v), (message: 'Enter a valid email address.', stale: false));
      const stale = AppError(type: AppErrorType.conflict, message: 'Changed by Ashish.', statusCode: 412);
      expect(customerWriteError(stale), (message: 'Changed elsewhere — Changed by Ashish.', stale: true));
    });
  });

  group('delete', () {
    test('gate from the record', () {
      expect(customerDeleteGate({'can_delete': true}), (allowed: true, reason: null));
      expect(customerDeleteGate({}), (allowed: true, reason: null));
      expect(customerDeleteGate({'can_delete': false, 'delete_blocked_reason': {'message': 'Converted.'}}),
          (allowed: false, reason: 'Converted.'));
      expect(customerDeleteGate({'can_delete': false}), (allowed: false, reason: customerNotDeletableCopy));
    });

    test('control: hidden / no permission / blocked', () {
      expect(customerDeleteControl(readOnly: true, canDelete: false, row: null).visible, isFalse);
      expect(customerDeleteControl(readOnly: false, canDelete: false, row: null),
          (visible: true, enabled: false, reason: deleteNoPermissionCopy));
      expect(customerDeleteControl(readOnly: false, canDelete: true, row: {'can_delete': false}).enabled, isFalse);
      expect(customerDeleteControl(readOnly: false, canDelete: true, row: {'can_delete': true}).enabled, isTrue);
      expect(isReadOnlyRole(read: true, create: false, update: false, delete: false), isTrue);
    });

    test('error copy', () {
      expect(customerDeleteErrorCopy(const AppError(type: AppErrorType.conflict, message: 'x', code: 'PARTY_HAS_BOOKS')),
          customerHasBooksCopy);
      expect(customerDeleteErrorCopy(const AppError(type: AppErrorType.forbidden, message: 'x')), deleteForbiddenCopy);
      expect(customerDeleteErrorCopy(const AppError(type: AppErrorType.notFound, message: 'x')), deleteNotFoundCopy);
    });
  });

  group('products', () {
    test('whole numbers only', () {
      expect(customerProductsPatch([(productId: 'p', quantity: '2')]).value, [
        {'product_id': 'p', 'quantity': 2},
      ]);
      expect(customerProductsPatch([(productId: 'p', quantity: '')]).value!.single['quantity'], 1);
      expect(customerProductsPatch([(productId: 'p', quantity: '3.0')]).value!.single['quantity'], 3);
      expect(customerProductsPatch([(productId: 'p', quantity: '1.5')]).error, customerQuantityError);
      expect(customerProductsPatch([(productId: 'p', quantity: '0')]).error, customerQuantityError);
      expect(customerQuantityError, 'Quantities on a customer are whole numbers (1, 2, 3 …).');
    });

    test('rows and text', () {
      final v = [
        {'product_id': 'a', 'product_name': 'Widget', 'quantity': 3},
        {'product_id': 'b', 'product_name': 'Gadget', 'quantity': '1.000'},
      ];
      expect(customerProductRows(v).map((r) => r.quantity), ['3', '1']);
      expect(productsText(v), 'Widget ×3, Gadget');
      expect(productsText([]), '—');
    });
  });

  test('assignees and picker options', () {
    final a = customerAssignees({
      'assignees': [
        {'user_id': 'u1', 'full_name': 'Neeraja Pradeep'},
        'u2',
      ],
    });
    expect(a.map((x) => x.name), ['Neeraja Pradeep', '']);
    expect(assignableNotAssigned<String>(['u1', 'u2', 'u3'], (u) => u, ['u1', 'u2']), ['u3']);
  });

  test('accounting panel gating', () {
    expect(showCustomerAccountingPanel(accountingActive: false, canDocs: true, canSettle: true, canSetup: true), isFalse);
    expect(showCustomerAccountingPanel(accountingActive: true, canDocs: false, canSettle: false, canSetup: false), isFalse);
    expect(showCustomerAccountingPanel(accountingActive: true, canDocs: true, canSettle: false, canSetup: false), isTrue);
  });
}
