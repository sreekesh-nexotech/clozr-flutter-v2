// Typed in-place editing of detail rows (CD-VS-012 / 014 / 016): which editor a
// column gets, how a custom value is written back, and that a role without the
// update right gets no editor.
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/record_rows.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';
import 'package:clozrapp/features/crm/presentation/components/inline_edit_row.dart';

ViewColumn _custom(String type, {List<(String, String)> choices = const []}) =>
    ViewColumn(
      name: 'custom_fields.x',
      label: 'X',
      order: 1,
      type: type == 'textarea' ? 'text' : (type == 'text' ? 'string' : type),
      isCustom: true,
      inFields: true,
      customType: type,
      choices: choices,
    );

ViewColumn _std(String type, {List<(String, String)> choices = const []}) =>
    ViewColumn(
        name: 'f',
        label: 'F',
        order: 1,
        type: type,
        inFields: true,
        choices: choices);

void main() {
  group('inlineKindOf', () {
    test('custom fields edit by their own type', () {
      expect(inlineKindOf(_custom('text')), InlineKind.text);
      expect(inlineKindOf(_custom('textarea')), InlineKind.multiline);
      expect(inlineKindOf(_custom('number')), InlineKind.number);
      expect(inlineKindOf(_custom('decimal')), InlineKind.number);
      expect(inlineKindOf(_custom('date')), InlineKind.date);
      expect(inlineKindOf(_custom('datetime')), InlineKind.datetime);
      expect(inlineKindOf(_custom('boolean')), InlineKind.boolean);
      expect(inlineKindOf(_custom('dropdown', choices: [('a', 'A')])),
          InlineKind.select);
      expect(inlineKindOf(_custom('multi_select', choices: [('a', 'A')])),
          InlineKind.multiselect);
    });

    test('a dropdown with no options is read-only rather than a dead editor',
        () {
      expect(inlineKindOf(_custom('dropdown')), InlineKind.none);
    });

    test('built-in boolean, date and choice columns edit too', () {
      expect(inlineKindOf(_std('boolean')), InlineKind.boolean);
      expect(inlineKindOf(_std('date')), InlineKind.date);
      expect(inlineKindOf(_std('string', choices: [('a', 'A')])),
          InlineKind.select);
      expect(inlineKindOf(_std('foreignkey')), InlineKind.none);
    });
  });

  group('inlineWriteBody', () {
    test('a plain field goes out under its own key', () {
      expect(inlineWriteBody('email', 'a@b.c', {}), {'email': 'a@b.c'});
    });

    test('a custom field keeps the record\'s other custom values', () {
      final body = inlineWriteBody('custom_fields.tier', 'Gold', {
        'custom_fields': {'budget': 5, 'tier': 'Silver'},
      });
      expect(body, {
        'custom_fields': {'budget': 5, 'tier': 'Gold'}
      });
    });

    test('clearing a custom field sends null for just that slug', () {
      final body = inlineWriteBody('custom_fields.tier', null, {
        'custom_fields': {'budget': 5, 'tier': 'Silver'},
      });
      expect(body['custom_fields'], {'budget': 5, 'tier': null});
    });
  });

  test('rawFieldValue reads custom values from custom_fields', () {
    final row = {
      'email': 'a@b.c',
      'custom_fields': {'x': 7}
    };
    expect(rawFieldValue(row, _custom('number')), 7);
    expect(rawFieldValue(row, _std('string')?.withLabel('E')), isNull);
  });

  testWidgets('a multi-line text field opens its editor without error',
      (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InlineEditRow(
              label: 'Requirement',
              display: '—',
              column: _std('text'),
              rawValue: null,
              editForm: 'Edit lead',
              onSave: (k, v) async => null,
              onBlocked: (_) {},
              child: const Text('row'),
            ),
          ),
        ),
      ),
    ));
    await tester.longPress(find.text('row'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  group('InlineEditRow permission', () {
    testWidgets('a role without update gets no editor and a reason',
        (tester) async {
      final blocked = <String>[];
      var saved = 0;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: InlineEditRow(
              label: 'X',
              display: '5',
              column: _custom('number'),
              rawValue: 5,
              editForm: 'Edit lead',
              canEdit: false,
              deniedHint: 'No update right',
              onSave: (k, v) async => saved++,
              onBlocked: blocked.add,
              child: const Text('row'),
            ),
          ),
        ),
      ));
      await tester.longPress(find.text('row'));
      await tester.pump();
      expect(blocked, ['No update right']);
      expect(find.byType(TextField), findsNothing);
      expect(saved, 0);
    });

    testWidgets('a role with update gets the box', (tester) async {
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: InlineEditRow(
              label: 'X',
              display: '5',
              column: _custom('number'),
              rawValue: 5,
              editForm: 'Edit lead',
              onSave: (k, v) async {},
              onBlocked: (_) {},
              child: const Text('row'),
            ),
          ),
        ),
      ));
      await tester.longPress(find.text('row'));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
