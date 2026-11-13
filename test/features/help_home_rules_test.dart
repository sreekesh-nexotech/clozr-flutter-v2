import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/features/helpdesk/application/help_home_rules.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/help_dashboard.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/help_kpis.dart';
import 'package:clozrapp/features/helpdesk/infrastructure/data_sources/remote/help_dashboard_remote_ds.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clozrapp/features/auth/application/providers/auth_providers.dart';
import 'package:clozrapp/features/auth/domain/entities/module_access.dart';
import 'package:clozrapp/features/helpdesk/application/providers/help_dashboard_providers.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiService {}

void main() {
  group('trendFor', () {
    const kpi = HelpKpi(count: 4, trendPct: 12);
    test('shows the chip only beside the count the server measured', () {
      expect(HelpHomeRules.trendFor(kpi, 4), kpi);
      expect(HelpHomeRules.trendFor(kpi, 0), isNull);
    });
    test('no chip without a trend or without a KPI', () {
      expect(HelpHomeRules.trendFor(const HelpKpi(count: 4), 4), isNull);
      expect(HelpHomeRules.trendFor(null, 0), isNull);
    });
  });

  group('SLA / priority donuts', () {
    const local = (within: 0, atRisk: 0, breached: 1);
    const localPri = (critical: 0, high: 1, medium: 0, low: 0);

    test('an all-zero server mix falls back to the cards\' figures', () {
      const empty = SlaPriorityMix();
      expect(HelpHomeRules.sla(empty, local), local);
      expect(HelpHomeRules.priority(empty, localPri), localPri);
      expect(HelpHomeRules.sla(null, local), local);
    });

    test('a server mix that counted something is used as sent', () {
      const mix = SlaPriorityMix(
          withinSla: 3, atRisk: 1, breached: 2, high: 4, critical: 2);
      expect(HelpHomeRules.sla(mix, local),
          (within: 3, atRisk: 1, breached: 2));
      expect(HelpHomeRules.priority(mix, localPri),
          (critical: 2, high: 4, medium: 0, low: 0));
    });
  });

  group('period reaches every Help Home request', () {
    late _MockApi api;
    setUp(() => api = _MockApi());

    test('KPIs, mix and grid send the period; custom adds from / to',
        () async {
      when(() => api.get(any(), query: any(named: 'query')))
          .thenAnswer((_) async => <String, dynamic>{});
      final ds = HelpDashboardRemoteDataSource(api);
      await ds.fetchKpis(period: 'last_month');
      await ds.fetchSlaPriorityMix(
          period: 'custom', from: '2026-10-01', to: '2026-10-15');
      await ds.fetchCompletedGrid(period: 'week');
      final q = verify(() => api.get(any(), query: captureAny(named: 'query')))
          .captured
          .cast<Map<String, String>>();
      expect(q[0], {'scope': 'own', 'period': 'last_month'});
      expect(q[1], {
        'scope': 'own',
        'period': 'custom',
        'from': '2026-10-01',
        'to': '2026-10-15'
      });
      expect(q[2], {'scope': 'own', 'period': 'week'});
    });

    test('a failing KPI call (403) answers null instead of throwing',
        () async {
      when(() => api.get(any(), query: any(named: 'query')))
          .thenThrow(Exception('403'));
      final ds = HelpDashboardRemoteDataSource(api);
      expect(await ds.fetchKpis(), isNull);
      expect(await ds.fetchSlaPriorityMix(), isNull);
      expect(await ds.fetchCompletedGrid(), isNull);
    });
  });

  group('scope=own is only personal for non-staff accounts', () {
    Future<bool> personal(ModuleAccess? a) {
      final probe = FutureProvider<bool>((ref) => serverOwnScopeIsPersonal(ref));
      final c = ProviderContainer(
          overrides: [moduleAccessProvider.overrideWith((ref) async => a)]);
      addTearDown(c.dispose);
      return c.read(probe.future);
    }

    test('staff admins are not (server answers org-wide)', () async {
      expect(await personal(const ModuleAccess(isStaff: true)), isFalse);
    });
    test('a non-staff user, or an unknown role, is', () async {
      expect(await personal(const ModuleAccess()), isTrue);
      expect(await personal(null), isTrue);
    });
  });
}
