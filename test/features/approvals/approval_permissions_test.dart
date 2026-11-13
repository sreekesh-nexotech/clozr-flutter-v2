// Unified Approvals — the permission model (route map §3): the entry is for
// everyone signed in and is never a landing screen; the Team tab follows the
// manager / admin flags with the probe as the fallback; unknown access never
// blocks anything.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/app/router/routes.dart';
import 'package:clozrapp/features/approvals/application/providers/approvals_providers.dart';
import 'package:clozrapp/features/approvals/domain/entities/approval.dart';
import 'package:clozrapp/features/approvals/domain/repositories/approvals_repository.dart';
import 'package:clozrapp/features/auth/application/providers/auth_providers.dart';
import 'package:clozrapp/features/auth/domain/entities/module_access.dart';
import 'package:clozrapp/features/notifications/application/notification_navigator.dart';
import 'package:clozrapp/features/notifications/infrastructure/data_sources/remote/notifications_remote_ds.dart';
import 'package:clozrapp/features/shell/domain/nav_catalog.dart';

Map<String, dynamic> _perm() => {'can_read': true};

ModuleAccess _access(
        {bool fullAccess = false,
        bool superuser = false,
        bool subordinates = false,
        List<String> modules = const []}) =>
    ModuleAccess.fromJson({
      'full_access': fullAccess,
      'is_superuser': superuser,
      'has_subordinates': subordinates,
      'modules': {for (final m in modules) m: _perm()},
    });

/// A repository whose Team tab holds [teamCount] rows.
class _FakeRepo implements ApprovalsRepository {
  _FakeRepo(this.teamCount);

  final int teamCount;
  int teamCalls = 0;

  @override
  Future<ApprovalPage> list(ApprovalListQuery query) async {
    if (query.tab == ApprovalTabs.team) teamCalls++;
    return ApprovalPage(count: teamCount, rows: const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<List<String>> _tabsFor(ModuleAccess? access, {int teamCount = 0}) async {
  final container = ProviderContainer(overrides: [
    moduleAccessProvider.overrideWith((ref) async => access),
    approvalsRepositoryProvider.overrideWithValue(_FakeRepo(teamCount)),
  ]);
  addTearDown(container.dispose);
  final sub = container.listen(approvalTabsProvider, (_, __) {});
  await container.read(moduleAccessProvider.future);
  await container.read(approvalsTeamProbeProvider.future);
  final tabs = container.read(approvalTabsProvider);
  sub.close();
  return tabs;
}

void main() {
  final entry = navCatalog.firstWhere((e) => e.key == approvalsNavKey);

  test('the Approvals entry is never module-gated', () {
    expect(entry.modules, isEmpty);
    expect(entry.path, Routes.approvals);
    for (final a in [
      _access(),
      _access(modules: ['payment']),
      _access(fullAccess: true, superuser: true, modules: ['settings']),
    ]) {
      expect(a.canAny(entry.modules), isTrue);
    }
  });

  test('…and never a landing screen', () {
    expect(entry.landing, isFalse);
    expect(landingPathFor(_access()), isNot(Routes.approvals));
    expect(landingPathFor(_access(modules: ['lead'])), isNot(Routes.approvals));
    expect(landingPathFor(null), Routes.dashboard);
  });

  group('Team tab', () {
    const all = ['pending', 'mine', 'team', 'history'];
    const noTeam = ['pending', 'mine', 'history'];

    test('a manager, a System Admin and a superuser see it', () async {
      expect(await _tabsFor(_access(subordinates: true)), all);
      expect(await _tabsFor(_access(fullAccess: true)), all);
      expect(await _tabsFor(_access(superuser: true)), all);
    });

    test('unknown access (mock mode, failed fetch) does not hide it',
        () async {
      expect(await _tabsFor(null), all);
    });

    test('anyone else sees it only once the probe finds rows', () async {
      expect(await _tabsFor(_access(modules: ['lead'])), noTeam);
      expect(await _tabsFor(_access(modules: ['project']), teamCount: 2), all);
    });
  });

  group('approval notifications open Approvals', () {
    AppNotificationRoute route(String type) {
      final n = notificationFromJson({
        'crm_notification_id': 'n1',
        'notification_type': type,
        'type': type,
        'title': 'x',
        'message': 'x',
        'created_at': '2026-11-03T09:12:44Z',
      });
      return (kind: n?.targetKind, id: n?.targetId);
    }

    test('waiting on the reader → Waiting for me', () {
      for (final t in [
        'ApprovalRequested',
        'ApprovalEscalated',
        'ApprovalRerouted'
      ]) {
        expect(route(t), (kind: 'list', id: 'approvalsPending'), reason: t);
      }
      expect(listRouteFor('approvalsPending'), Routes.approvals);
    });

    test('an outcome → My requests; legacy due-date → the due-date filter',
        () {
      expect(route('ApprovalDecided').id, 'approvalsMine');
      expect(route('ApprovalClosed').id, 'approvalsMine');
      expect(route('DueDateChangeRequested').id, 'approvalsDueDate');
      expect(route('DueDateChangeDecided').id, 'approvalsMine');
      expect(listRouteFor('approvalsMine'), '${Routes.approvals}?tab=mine');
      expect(listRouteFor('approvalsDueDate'),
          '${Routes.approvals}?kind=due_date');
    });
  });
}

typedef AppNotificationRoute = ({String? kind, String? id});
