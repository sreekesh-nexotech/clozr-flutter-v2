// Unified Approvals — the screens, against the mock-backed repository: the
// tabs and cards render, a reject needs a real reason, the record banner
// follows the server's `can_*` flags, and an empty tab says so.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/approvals/application/approval_rules.dart';
import 'package:clozrapp/features/approvals/application/providers/approvals_providers.dart';
import 'package:clozrapp/features/approvals/domain/entities/approval.dart';
import 'package:clozrapp/features/approvals/domain/repositories/approvals_repository.dart';
import 'package:clozrapp/features/approvals/infrastructure/data_sources/local/approvals_mock_ds.dart';
import 'package:clozrapp/features/approvals/infrastructure/repositories/approvals_repository_impl.dart';
import 'package:clozrapp/features/approvals/presentation/components/approval_decision_dialog.dart';
import 'package:clozrapp/features/approvals/presentation/components/approval_parts.dart';
import 'package:clozrapp/features/approvals/presentation/screens/approvals_screen.dart';
import 'package:clozrapp/features/auth/application/providers/auth_providers.dart';

Widget _host(Widget child, {ApprovalsRepository? repo}) => ProviderScope(
      overrides: [
        moduleAccessProvider.overrideWith((ref) async => null),
        approvalsRepositoryProvider.overrideWithValue(
            repo ?? ApprovalsRepositoryImpl(const ApprovalsMockDataSource())),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(home: Scaffold(body: child)),
      ),
    );

/// A repository with nothing in it, and a record state of our choosing.
class _EmptyRepo implements ApprovalsRepository {
  _EmptyRepo({this.record = const RecordApprovalState()});

  final RecordApprovalState record;

  @override
  Future<ApprovalPage> list(ApprovalListQuery query) async => ApprovalPage.empty;

  @override
  Future<ApprovalCounts> counts() async => ApprovalCounts.zero;

  @override
  Future<RecordApprovalState> forRecord(String module, String objectId) async =>
      record;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('the list shows the tabs, the count and the waiting requests',
      (tester) async {
    await tester.pumpWidget(_host(const ApprovalsScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Unknown access (mock mode) never hides the Team tab.
    expect(find.text('Waiting for me · 2'), findsOneWidget);
    expect(find.text('My requests'), findsOneWidget);
    // The tab row scrolls sideways (the later chips are built as they scroll
    // in), so the full set is read from the provider that drives it.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(ApprovalsScreen)));
    expect(container.read(approvalTabsProvider),
        ['pending', 'mine', 'team', 'history']);
    expect(find.text('Send proposal to Acme'), findsOneWidget);
    expect(find.text('Task · Closing'), findsOneWidget);
    // The Quote discount approvals link now always sits above the list
    // (UI/UX audit #23), so the last request may start below the fold.
    await tester.dragUntilVisible(find.text('Lead · Owner transfer'),
        find.byType(ListView).last, const Offset(0, -200));
    expect(find.text('Lead · Owner transfer'), findsOneWidget);
    // Requests the viewer raised are not in Waiting for me.
    expect(find.text('Site survey'), findsNothing);

    await tester.ensureVisible(find.text('My requests'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My requests'));
    await tester.pumpAndSettle();
    expect(find.text('Site survey'), findsOneWidget);
    expect(find.text('Send proposal to Acme'), findsNothing);
  });

  testWidgets('a ?kind= deep link starts filtered', (tester) async {
    await tester.pumpWidget(
        _host(const ApprovalsScreen(initialTab: 'mine', initialKind: 'due_date')));
    await tester.pumpAndSettle();
    expect(find.text('Site survey'), findsOneWidget);
    expect(find.text('Clear filters'), findsWidgets);
  });

  testWidgets('an empty tab says so in the webapp words', (tester) async {
    await tester.pumpWidget(_host(const ApprovalsScreen(), repo: _EmptyRepo()));
    await tester.pumpAndSettle();
    expect(find.text('Nothing is waiting for you'), findsOneWidget);
    expect(find.text('Waiting for me'), findsOneWidget);
  });

  testWidgets('reject stays disabled until the reason has 10 characters',
      (tester) async {
    var submitted = '';
    await tester.pumpWidget(_host(Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showDialog<bool>(
            context: context,
            builder: (_) => ApprovalNoteDialog(
              action: ApprovalAction.reject,
              subject: 'Send proposal',
              change: 'In progress → Completed',
              submit: (note) async => submitted = note,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Reject: Send proposal'), findsOneWidget);

    TextButton confirm() => tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Reject').last);
    expect(confirm().onPressed, isNull);
    expect(find.text('At least 10 characters.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'too short');
    await tester.pump();
    expect(confirm().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Customer replied yesterday');
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
    await tester.tap(find.widgetWithText(TextButton, 'Reject').last);
    await tester.pumpAndSettle();
    expect(submitted, 'Customer replied yesterday');
  });

  testWidgets('the record banner shows only what the viewer may do',
      (tester) async {
    final repo = _EmptyRepo(
      record: const RecordApprovalState(
        pending: PendingApproval(
          id: 'a1',
          kind: 'close',
          to: 'Completed',
          approverName: 'Priya Nair',
          canWithdraw: true,
        ),
      ),
    );
    await tester.pumpWidget(_host(
        const ApprovalBanner(module: 'task', objectId: 't1'),
        repo: repo));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'Closing to Completed is waiting for approval from Priya Nair'),
        findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Escalate'), findsNothing);
  });

  testWidgets('no banner when nothing waits on the record', (tester) async {
    await tester.pumpWidget(_host(
        const ApprovalBanner(module: 'task', objectId: 't1'),
        repo: _EmptyRepo()));
    await tester.pumpAndSettle();
    expect(find.textContaining('waiting for approval'), findsNothing);
  });
}
