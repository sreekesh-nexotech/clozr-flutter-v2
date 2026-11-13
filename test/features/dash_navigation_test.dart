import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/helpdesk/application/filters/ticket_query.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/application/providers/leads_providers.dart';

import 'package:clozrapp/app/router/routes.dart';
import 'package:clozrapp/features/crm/application/providers/crm_home_providers.dart';
import 'package:clozrapp/features/dashboard/application/dash_navigation.dart';
import 'package:flutter/material.dart' show DateTimeRange;

/// Dashboard card links: which screen, which filter, and what the router
/// receives once the CRM presets are consumed.
void main() {
  test('CRM list presets are consumed; the path alone reaches the router', () {
    final l = DashLink.parse('${Routes.leads}?group=lost');
    expect(l.path, Routes.leads);
    expect(l.params, {'group': 'lost'});
    expect(l.target, Routes.leads);
    expect(l.isDetail, isFalse);

    final p = DashLink.parse('${Routes.payments}?mode=payments&tab=overdue');
    expect(p.params, {'mode': 'payments', 'tab': 'overdue'});
    expect(p.target, Routes.payments);
  });

  test('params the target screen reads itself stay on the URL', () {
    final t = DashLink.parse('${Routes.tickets}?all=1&breaching=1');
    expect(t.target, '${Routes.tickets}?all=1&breaching=1');
    final o = DashLink.parse('${Routes.opsTasks}?assignee=u1');
    expect(o.target, '${Routes.opsTasks}?assignee=u1');
    final pr = DashLink.parse('${Routes.opsProjects}?status=s1');
    expect(pr.target, '${Routes.opsProjects}?status=s1');
  });

  test('record links are detail routes (pushed, not replaced)', () {
    for (final r in [
      '${Routes.opsTaskDetail}?id=t1',
      '${Routes.projectDetail}?id=p1',
      '${Routes.ticketDetail}?id=i1',
      '${Routes.customerDetail}?id=c1',
    ]) {
      final l = DashLink.parse(r);
      expect(l.isDetail, isTrue, reason: r);
      expect(l.target, r);
    }
    expect(DashLink.parse(Routes.leads).isDetail, isFalse);
  });

  test('Home links: mine / group / tab presets are consumed, due stays', () {
    expect(DashLink.parse('${Routes.tickets}?mine=1&group=resolved').target,
        Routes.tickets);
    expect(DashLink.parse('${Routes.tickets}?mine=1&breaching=1').target,
        '${Routes.tickets}?breaching=1');
    expect(DashLink.parse('${Routes.opsTasks}?mine=1&due=overdue').target,
        '${Routes.opsTasks}?mine=1&due=overdue');
    expect(DashLink.parse('${Routes.opsTasks}?mine=1&tab=completed').target,
        '${Routes.opsTasks}?mine=1');
    expect(DashLink.parse('${Routes.opsProjects}?mine=1&group=open').target,
        Routes.opsProjects);
    expect(DashLink.parse('${Routes.leads}?stage=qualified').target,
        Routes.leads);
  });

  test('Leads owner / from / to are consumed (applied as drawer facets)', () {
    final l = DashLink.parse(
        '${Routes.leads}?owner=u1&from=2026-11-01&to=2026-11-04&group=won');
    expect(l.params['owner'], 'u1');
    expect(l.target, Routes.leads);
  });

  test('crmPeriodRange mirrors the server windows', () {
    final today = DateTime(2026, 11, 4);
    expect(crmPeriodRange(CrmPeriod.thisMonth, today: today),
        (from: DateTime(2026, 11, 1), to: today));
    expect(crmPeriodRange(CrmPeriod.lastMonth, today: today),
        (from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31)));
    expect(crmPeriodRange(CrmPeriod.thisQuarter, today: today),
        (from: DateTime(2026, 10, 1), to: today));
    expect(crmPeriodRange(CrmPeriod.ytd, today: today),
        (from: DateTime(2026, 1, 1), to: today));
    expect(crmPeriodRange(CrmPeriod.last30, today: today).from,
        DateTime(2026, 10, 6));
    expect(crmPeriodRange(CrmPeriod.last90, today: today).from,
        DateTime(2026, 8, 7));
    expect(
        crmPeriodRange(CrmPeriod.custom,
            today: today,
            custom: DateTimeRange(
                start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 15))),
        (from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 15)));
    expect(crmPeriodQuery(CrmPeriod.thisMonth, null),
        startsWith('from=${DateTime.now().year}-'));
  });

  test('CRM tab Leads links carry the period window, team and member', () {
    final today = DateTime(2026, 11, 4);
    final l = leadsLinkScoped(Routes.leads,
        periodLabel: 'This month', today: today);
    expect(l, contains('from=2026-11-01'));
    expect(l, contains('to=2026-11-04'));
    final w = leadsLinkScoped('${Routes.leads}?group=won',
        periodLabel: 'Last month', team: 't1', member: 'u1', today: today);
    expect(w, contains('group=won'));
    expect(w, contains('from=2026-10-01'));
    expect(w, contains('to=2026-10-31'));
    expect(w, contains('team=t1'));
    expect(w, contains('owner=u1'));
    // A row's own owner wins over the member filter; pseudo-teams are dropped.
    final e = leadsLinkScoped('${Routes.leads}?owner=u9',
        periodLabel: 'This month', team: 'individual', member: 'u1', today: today);
    expect(e, contains('owner=u9'));
    expect(e, isNot(contains('u1')));
    expect(e, isNot(contains('team=')));
    // Non-Leads routes are untouched.
    expect(leadsLinkScoped('${Routes.payments}?tab=overdue', periodLabel: 'This month'),
        '${Routes.payments}?tab=overdue');
  });

  test('period=1 on a card route becomes the Dashboard window', () {
    final today = DateTime(2026, 11, 4);
    final r = withDashPeriod('${Routes.payments}?mode=payments&tab=paid&period=1',
        periodLabel: 'Last 30 days', today: today);
    expect(r, isNot(contains('period=1')));
    expect(r, contains('from=2026-10-06'));
    expect(r, contains('to=2026-11-04'));
    expect(r, contains('tab=paid'));
    expect(withDashPeriod('${Routes.leads}?pipeline=open', periodLabel: 'This month'),
        '${Routes.leads}?pipeline=open');
    final l = DashLink.parse('${Routes.payments}?mode=payments&tab=overdue&cust=c1');
    expect(l.params['cust'], 'c1');
    expect(l.target, Routes.payments);
    expect(DashLink.parse('${Routes.tickets}?all=1&open=1').target, '${Routes.tickets}?all=1');
  });

  test('pipeline scope folds the status counts to the kept types', () {
    final counts = {
      'all': 34,
      'group:new': 19,
      'group:in_progress': 12,
      'group:won': 2,
      'group:lost': 1,
      'group:junk': 0,
    };
    final out = narrowCountsToStatusTypes(counts, 'new,in_progress,won,junk');
    expect(out['all'], 33);
    expect(out['group:lost'], 0);
    expect(out['group:won'], 2);
    expect(narrowCountsToStatusTypes(counts, null), counts);
  });

  test('open-only ticket scope folds the resolved statuses out of the chips', () {
    const catalog = [
      CatalogOption(id: 'o1', name: 'Open'),
      CatalogOption(id: 'r1', name: 'Resolved', isClosed: true),
      CatalogOption(id: 'r2', name: 'Closed', isClosed: true),
    ];
    final out = hideResolvedCounts(
        {'all': 6, 'o1': 3, 'r1': 2, 'r2': 1, 'open': 3, 'resolved': 3, 'group:resolved': 3},
        catalog);
    expect(out['all'], 3);
    expect(out['r1'], 0);
    expect(out['resolved'], 0);
    expect(out['group:resolved'], 0);
    expect(out['open'], 3);
  });
}
