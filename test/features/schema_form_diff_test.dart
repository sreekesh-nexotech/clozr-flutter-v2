// `LeadSchemaForm.payload` used to return the current value of **every**
// editable column, never comparing against the record it had been seeded from.
// Two things fell out of that: `payload` was never empty, so the edit screen's
// "Nothing to save" branch was unreachable and an untouched Save posted a
// PATCH; and every save rewrote all of the org's configured columns, touched or
// not — which for a `manytomany` meant resending a list that could be empty if
// its catalog had not loaded.
//
// `diffAgainstRow` is the opt-in that makes the payload a difference. It is
// opt-in rather than inferred from `row != null` because the add-lead screen
// passes `row: {}` for a brand-new record, so "has a row" does not mean "is an
// edit" — these tests pin both halves of that.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:clozrapp/features/crm/presentation/components/lead_schema_form.dart';

/// Two plain text columns plus a foreign key and a many-to-many, so the
/// unchanged-means-omitted rule is exercised on every branch of `payload`.
const _schemaBody = {
  'model': 'Customer',
  'view_type': 'detail',
  'has_org_config': true,
  'all_fields': {
    'columns': [
      {
        'name': 'name',
        'label': 'Customer',
        'order': 1,
        'visible': true,
        'in_fields': true,
        'field_info': {'name': 'name', 'type': 'string'},
      },
      {
        'name': 'organization_name',
        'label': 'Organization',
        'order': 2,
        'visible': true,
        'in_fields': true,
        'field_info': {'name': 'organization_name', 'type': 'string'},
      },
      {
        'name': 'status',
        'label': 'Status',
        'order': 3,
        'visible': true,
        'in_fields': true,
        'field_info': {
          'name': 'status',
          'type': 'foreignkey',
          'related_model': 'CustomerStatus',
        },
      },
      {
        'name': 'assignees',
        'label': 'Assignees',
        'order': 4,
        'visible': true,
        'in_fields': true,
        'field_info': {
          'name': 'assignees',
          'type': 'manytomany',
          'related_model': 'User',
        },
      },
    ],
  },
};

const _row = <String, dynamic>{
  'name': 'Vikram Singh',
  'organization_name': 'Acme Interiors',
  'status': 'status-uuid-1',
  'assignees': <dynamic>[],
};

Future<LeadSchemaFormState> _pump(
  WidgetTester tester, {
  required bool diffAgainstRow,
  Map<String, dynamic>? row = _row,
}) async {
  final key = GlobalKey<LeadSchemaFormState>();
  await tester.pumpWidget(
    ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LeadSchemaForm(
                key: key,
                schema: ViewSchema.fromResponse(_schemaBody),
                row: row,
                // Customers write status as plain `status`, not the Lead
                // mapping's `status_id`.
                writeKey: (c) => c.name,
                diffAgainstRow: diffAgainstRow,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

void main() {
  group('edit (diffAgainstRow: true)', () {
    testWidgets('an untouched form sends nothing at all', (tester) async {
      final state = await _pump(tester, diffAgainstRow: true);
      // The whole point: empty is what lets the caller say "Nothing to save".
      expect(state.payload, isEmpty);
    });

    testWidgets('only the edited column is sent', (tester) async {
      final state = await _pump(tester, diffAgainstRow: true);
      await tester.enterText(find.text('Acme Interiors'), 'QA Test Org');
      await tester.pump();

      expect(state.payload, {'organization_name': 'QA Test Org'});
      // `name` was seeded and left alone, so it must not be resent — that
      // blanket rewrite is the second half of the bug.
      expect(state.payload.containsKey('name'), isFalse);
      // A `manytomany` used to be posted unconditionally, which could clear
      // assignees outright when its catalog had not resolved.
      expect(state.payload.containsKey('assignees'), isFalse);
    });

    testWidgets('editing then restoring a value reads as unchanged',
        (tester) async {
      final state = await _pump(tester, diffAgainstRow: true);
      await tester.enterText(find.text('Acme Interiors'), 'Something else');
      await tester.pump();
      expect(state.payload, isNotEmpty);

      await tester.enterText(find.text('Something else'), 'Acme Interiors');
      await tester.pump();
      expect(state.payload, isEmpty);
    });

    testWidgets('clearing a seeded box is an edit, and clears the field',
        (tester) async {
      final state = await _pump(tester, diffAgainstRow: true);
      await tester.enterText(find.text('Acme Interiors'), '');
      await tester.pump();
      // Present, not omitted: the box was prefilled, so emptying it means
      // "clear this" rather than "leave it be". The value is `''` — only the
      // numeric types coerce an emptied box to null (`schemaWriteValue`).
      expect(state.payload.containsKey('organization_name'), isTrue);
      expect(state.payload['organization_name'], '');
    });
  });

  group('create (diffAgainstRow: false — the default)', () {
    testWidgets('every rendered column is still sent', (tester) async {
      final state = await _pump(tester, diffAgainstRow: false);
      // Unchanged behaviour for the six create/add call sites that share this
      // form; only the customer edit screen opts into diffing.
      expect(state.payload.containsKey('name'), isTrue);
      expect(state.payload.containsKey('organization_name'), isTrue);
      expect(state.payload.containsKey('assignees'), isTrue);
    });

    testWidgets('a blank new record still sends its columns', (tester) async {
      // `row: {}` is what add-lead passes — non-null, but not an edit.
      final state = await _pump(tester, diffAgainstRow: false, row: const {});
      expect(state.payload, isNotEmpty);
    });
  });
}
