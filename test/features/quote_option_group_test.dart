import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/quote_lifecycle.dart';
import 'package:clozrapp/features/crm/domain/entities/quote.dart';
import 'package:clozrapp/features/crm/presentation/components/quote_detail/quote_dialogs.dart';

Quote _q(String id, {String group = '', String label = '', String role = ''}) =>
    Quote(
      id: id,
      custId: null,
      leadId: null,
      status: 'draft',
      amount: '₹1',
      amountNum: 1,
      issued: '',
      valid: '—',
      template: '',
      payType: '',
      currency: 'INR',
      dueDate: '',
      owner: '',
      items: const [],
      optionGroupId: group,
      optionLabel: label,
      optionRole: role,
    );

void main() {
  test('QuoteFacts reads the option group, label and role', () {
    final f = QuoteFacts.fromRow({
      'quotation_id': 'q1',
      'option_group': 'g1',
      'option_label': 'B',
      'option_role': 'alternative',
    });
    expect(f.isGrouped, isTrue);
    expect(f.optionGroupId, 'g1');
    expect(f.optionLabel, 'B');
    final plain = QuoteFacts.fromRow({'quotation_id': 'q2'});
    expect(plain.isGrouped, isFalse);
  });

  test('a grouped row shows "Option B · alternative"', () {
    expect(_q('a', group: 'g', label: 'B', role: 'alternative').optionChip,
        'Option B · alternative');
    expect(_q('a').optionChip, '');
  });

  test('options of a group sit together, A → C, at the group\'s first row', () {
    final rows = [
      _q('x'),
      _q('b', group: 'g', label: 'B'),
      _q('y'),
      _q('a', group: 'g', label: 'A'),
      _q('c', group: 'g', label: 'C'),
    ];
    final out = groupedQuoteOrder(rows);
    expect([for (final r in out) r.id], ['x', 'a', 'b', 'c', 'y']);
    expect(isFollowingOption(out, 2), isTrue);
    expect(isFollowingOption(out, 1), isFalse);
  });

  testWidgets('the Accept dialog makes staff pick an option, none preselected',
      (tester) async {
    AcceptChoice? sent;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => showAcceptQuoteDialog(
                  ctx,
                  quote: const QuoteFacts(
                      id: 'q', number: 'QTN-1', validUntil: '2099-01-01'),
                  amountLabel: '',
                  options: const [
                    (id: 'a', label: 'Option A · QTN-1', amount: '₹10'),
                    (id: 'b', label: 'Option B · QTN-2', amount: '₹20'),
                  ],
                  onSubmit: (c) async {
                    sent = c;
                    return null;
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Which option did the customer accept?'), findsOneWidget);
    expect(find.text('Accept option'), findsOneWidget);

    await tester.tap(find.text('Accept option'));
    await tester.pumpAndSettle();
    expect(find.text('Pick the option the customer accepted.'), findsOneWidget);
    expect(sent, isNull);

    await tester.tap(find.text('Option B · QTN-2'));
    await tester.pumpAndSettle();
    expect(find.text('Accept Option B'), findsOneWidget);
    await tester.tap(find.text('Accept Option B'));
    await tester.pumpAndSettle();
    expect(sent?.optionId, 'b');
  });
}
