// Items 3 and 8 of the Dashboard/Reports/Billing QA pass: every entry in the
// drawer is gated on the module keys `/auth/me/modules/` returns, so a role
// without `settings` never sees Billing and one without `report` never sees
// Reports. None of the QA accounts is restricted (all three come back
// `full_access: true` with every module), so this exercises the gate with the
// real payload shape minus those two keys instead.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/app/router/routes.dart';
import 'package:clozrapp/features/auth/domain/entities/module_access.dart';
import 'package:clozrapp/features/shell/domain/nav_catalog.dart';

Map<String, dynamic> _perm(String label) => {
      'label': label,
      'can_read': true,
      'can_create': false,
      'can_update': false,
      'can_delete': false,
      'can_export': false,
      'can_import': false,
      'can_approve': false,
    };

/// A "CRM User" as the backend would describe one: leads, customers, tasks —
/// no settings, no report, no dashboard.
ModuleAccess _crmUser() => ModuleAccess.fromJson({
      'full_access': false,
      'roles': ['CRM User'],
      'modules': {
        'lead': _perm('Leads'),
        'customer': _perm('Customers'),
        'followup': _perm('Follow-ups'),
        'task': _perm('Tasks'),
        'payment': _perm('Payments'),
      },
      'sidebar': ['lead', 'customer', 'followup', 'task', 'payment'],
    });

ModuleAccess _admin() => ModuleAccess.fromJson({
      'full_access': true,
      'roles': <String>[],
      'modules': {
        for (final k in ['dashboard', 'lead', 'report', 'settings', 'payment'])
          k: _perm(k),
      },
    });

Iterable<String> _visible(ModuleAccess a) =>
    navCatalog.where((e) => a.canAny(e.modules)).map((e) => e.key);

void main() {
  _dashboardTabs();
  test('Billing and Reports are hidden without settings / report', () {
    final keys = _visible(_crmUser()).toList();
    expect(keys, isNot(contains('billing')));
    expect(keys, isNot(contains('reports')));
    expect(keys, isNot(contains('dashboard')));
    expect(keys, contains('crm'));
  });

  test('the CRM payment module alone does not unlock Billing', () {
    final a = ModuleAccess.fromJson({
      'modules': {'payment': _perm('Payments')},
    });
    expect(_visible(a), ['crm']);
  });

  test('an admin sees Billing, Reports and Dashboard', () {
    final keys = _visible(_admin()).toList();
    expect(keys, containsAll(['dashboard', 'reports', 'billing']));
  });

  test('a restricted role lands on its first visible entry, not Dashboard', () {
    expect(landingPathFor(_crmUser()), isNot(Routes.dashboard));
    expect(landingPathFor(_admin()), Routes.dashboard);
    // Unknown access (mock mode / fetch failed) is not guessed away.
    expect(landingPathFor(null), Routes.dashboard);
  });
}

void _dashboardTabs() {
  test('Dashboard panel tabs follow the webapp dashboard modules', () {
    expect(visibleDashboardTabs(_crmUser()), isEmpty);
    // Legacy payload: a bare `dashboard` key keeps Business only.
    expect(visibleDashboardTabs(_admin()), ['business']);
    expect(visibleDashboardTabs(null), ['business', 'crm', 'ops', 'help']);
    final helpOnly = ModuleAccess.fromJson({
      'modules': {'issue_dashboard': _perm('Issue Dashboard'), 'issue': _perm('Issues')},
    });
    expect(visibleDashboardTabs(helpOnly), ['help']);
  });

  test('the live dashboard grants unlock the Dashboard like the webapp', () {
    // System Admin as dev.clozr.tech returns it: four *_dashboard keys, no plain `dashboard`.
    final admin = ModuleAccess.fromJson({
      'modules': {
        for (final k in ['admin_dashboard', 'crm_dashboard', 'pmo_dashboard', 'issue_dashboard', 'lead'])
          k: _perm(k),
      },
    });
    expect(_visible(admin), contains('dashboard'));
    expect(landingPathFor(admin), Routes.dashboard);
    expect(visibleDashboardTabs(admin), ['business', 'crm', 'ops', 'help']);

    // CRM User + Helpdesk + PMO: no admin_dashboard → no Business tab.
    final mixed = ModuleAccess.fromJson({
      'modules': {
        for (final k in ['crm_dashboard', 'pmo_dashboard', 'issue_dashboard', 'lead']) k: _perm(k),
      },
    });
    expect(_visible(mixed), contains('dashboard'));
    expect(visibleDashboardTabs(mixed), ['crm', 'ops', 'help']);
  });
}
