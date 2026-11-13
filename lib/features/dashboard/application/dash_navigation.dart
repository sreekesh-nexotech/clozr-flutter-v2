import 'package:flutter/material.dart' show BuildContext, DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/api_config.dart';
import '../../../core/filters/filter_models.dart';
import '../../crm/application/filters/leads_filter_spec.dart';
import '../../crm/application/filters/followups_filter_spec.dart';
import '../../crm/application/filters/payments_filter_spec.dart';
import '../../crm/application/filters/quotes_filter_spec.dart';
import '../../crm/application/filters/tasks_filter_spec.dart';
import '../../crm/application/providers/crm_catalog_providers.dart';
import '../../crm/application/providers/crm_home_providers.dart'
    show CrmPeriod, crmPeriodRange;
import '../../crm/application/providers/crm_tasks_providers.dart';
import '../../crm/application/providers/followups_providers.dart';
import '../../crm/application/providers/leads_providers.dart';
import '../../crm/application/providers/payments_providers.dart';
import '../../crm/application/providers/quotes_providers.dart';
import '../../crm/application/providers/saved_filters_providers.dart';
import '../../helpdesk/application/providers/tickets_providers.dart';
import '../../operations/application/filters/ops_tasks_filter_spec.dart';
import '../../operations/application/filters/projects_filter_spec.dart';
import '../../operations/application/providers/ops_tasks_providers.dart';
import '../../operations/application/providers/projects_providers.dart';
import 'providers/dashboard_providers.dart';

/// What a Dashboard card links to: the screen, and the filter the list must
/// open on so it shows the figure the card counted — never the whole list
/// behind a card that said "3 overdue".
///
/// The Helpdesk, Operations tasks and Projects screens read their own query
/// params on entry (`all`, `breaching`, `sla`, `pri`, `cat`, `assignee`,
/// `due`, `project`, `end`, `status`). The CRM lists (Leads, Payments,
/// Follow-ups, Tasks, Quotes) keep their selection in providers instead, so
/// [dashGo] applies these keys to those providers before navigating:
///
/// | screen     | key      | value                                   |
/// | Leads      | `group`  | status TYPE: `won`, `lost`, `in_progress` |
/// | Leads      | `stage`  | a lead status id or key                 |
/// | Leads      | `source` | a lead-source id                        |
/// | Leads      | `owner`  | a user id (assigned to)                 |
/// | Leads      | `team`   | a team id (assigned team)               |
/// | Leads      | `mine`   | `1` = owner or assignee is me (`is_teams`) |
/// | Leads      | `pipeline` | `open` = not converted, not lost (the sales pipeline) |
/// | Payments   | `from`/`to` | payment-date window; `cust` = a customer name (the rows carry no id) |
/// | Tickets    | `open`   | `1` = hide resolved statuses            |
/// | Leads      | `from`/`to` | created-in window, YYYY-MM-DD        |
/// | Payments   | `mode`   | `payments` (plans) or `invoices`        |
/// | Payments   | `tab`    | `paid`, `due`, `overdue`, `scheduled`   |
/// | Follow-ups | `tab`    | `overdue`                               |
/// | Tasks      | `tab`    | `overdue`                               |
/// | Quotes     | `status` | a status key, e.g. `accepted`           |
/// | Tickets    | `group`  | a status group, e.g. `resolved` (`all` = My/All via `all`) |
/// | Ops tasks  | `mine`   | `1` = My Tasks (stays on the URL); `tab` = `completed` |
/// | Projects   | `mine`   | `1` = My Projects; `group` = `open`/`closed`; `tab` = status chips |
class DashLink {
  const DashLink(this.path, this.params);

  /// The route without the query the lists do not read themselves.
  final String path;
  final Map<String, String> params;

  /// Routes that open a single record are pushed over the Dashboard, so Back
  /// returns to the tab the user was on; lists replace it (the bottom bar
  /// switches module).
  bool get isDetail => path.endsWith('/detail');

  static DashLink parse(String route) {
    final uri = Uri.parse(route);
    return DashLink(uri.path, Map<String, String>.from(uri.queryParameters));
  }

  /// The keys [dashGo] consumes itself; anything else stays on the URL for the
  /// target screen to read.
  static const _presetKeys = {
    Routes.leads: {
      'group',
      'stage',
      'source',
      'owner',
      'team',
      'from',
      'to',
      'mine',
      'pipeline',
      'owned'
    },
    Routes.payments: {'mode', 'tab', 'from', 'to', 'cust'},
    Routes.followups: {'tab', 'from', 'to', 'mine'},
    Routes.tasks: {'tab', 'from', 'to', 'mine'},
    Routes.quotes: {'status', 'from', 'to'},
    Routes.tickets: {'group', 'mine', 'open', 'from', 'to'},
    Routes.opsTasks: {'tab', 'group'},
    Routes.opsProjects: {'mine', 'tab', 'group'},
  };

  /// The route to hand to the router: the path plus the params the target
  /// screen reads on its own.
  String get target {
    final consumed = _presetKeys[path] ?? const <String>{};
    final rest = {
      for (final e in params.entries)
        if (!consumed.contains(e.key)) e.key: e.value
    };
    return rest.isEmpty
        ? path
        : Uri(path: path, queryParameters: rest).toString();
  }
}

/// Opens [route] from a Dashboard card, pre-setting the target list's own
/// selection from the route's query (see [DashLink]).
void dashGo(BuildContext context, WidgetRef ref, String route) {
  final link = DashLink.parse(route);
  _preset(ref, link);
  if (link.isDetail) {
    context.push(link.target);
  } else {
    context.go(link.target);
  }
}

/// A dashboard link means exactly its slice. The list screens keep their
/// drawer filters, status chips and My/All toggles across visits, so without
/// this the second link inherits the first: "SLA Breaches" then "Avg
/// Resolution" showed the breached tickets again, and a Project Status slice
/// after "Projects Overdue" was ANDed with the overdue window. The target
/// screen then applies the link's own params on top of a clean state.
void _preset(WidgetRef ref, DashLink link) {
  final p = link.params;
  switch (link.path) {
    case Routes.tickets:
      ref.read(ticketFiltersProvider.notifier).state = FilterValues();
      ref.read(ticketBreachingProvider.notifier).state = false;
      ref.read(ticketOpenOnlyProvider.notifier).state = p['open'] == '1';
      // A created window (the period a Helpdesk figure covers).
      ref.read(ticketScopeParamsProvider.notifier).state = {
        if ((p['from'] ?? '').isNotEmpty) 'created_at_after': p['from']!,
        if ((p['to'] ?? '').isNotEmpty) 'created_at_before': p['to']!,
      };
      ref.read(ticketMineProvider.notifier).state = p['all'] != '1';
      // A status group ("resolved"): the header's group plus its folded chip,
      // as Help Home's resolved grid opens it.
      final group = p['group'];
      final hasGroup = group != null && group.isNotEmpty && group != 'all';
      ref.read(ticketGroupProvider.notifier).state = hasGroup ? group : null;
      ref.read(ticketStatusChipsProvider.notifier).state =
          hasGroup ? {group} : const {};
      ref.read(ticketSavedFiltersProvider.notifier).deactivate();
    case Routes.opsTasks:
      ref.read(opsTaskFiltersProvider.notifier).state = FilterValues();
      // `group=open` = the header's open group (not completed / cancelled).
      final tGroup = p['group'];
      ref.read(otGroupProvider.notifier).state =
          tGroup == null || tGroup.isEmpty ? null : tGroup;
      // "completed" is the org's done status (a status id in API mode).
      final done = ref.read(opsTaskDoneStatusProvider);
      ref.read(otTabsProvider.notifier).state = p['tab'] == 'completed'
          ? {ApiConfig.apiEnabled && done != null ? done.id : 'completed'}
          : const <String>{};
      // The Dashboard counts the whole org; the Homes count the user's own
      // (`mine=1`, which the Tasks screen also reads for its `due` slice).
      ref.read(myTasksFProvider.notifier).state = p['mine'] == '1';
    case Routes.opsProjects:
      ref.read(projectFiltersProvider.notifier).state = FilterValues();
      ref.read(myProjectsProvider.notifier).state = p['mine'] == '1';
      // `group` is the header's status group (`open` = not closed, `closed`);
      // `tab` a status chip (status names). A "live projects" link uses the
      // group: there is no chip literally named "active".
      final group = p['group'];
      ref.read(projGroupProvider.notifier).state =
          group == null || group.isEmpty || group == 'all' ? null : group;
      ref.read(projTabProvider.notifier).state =
          (p['tab'] == null || p['tab']!.isEmpty) ? 'all' : p['tab']!;
    case Routes.leads:
      // A dashboard figure is a fresh slice: clear what the list had picked.
      ref.read(leadGroupProvider.notifier).state = p['group'];
      final stage = p['stage'];
      ref.read(leadTabProvider.notifier).state = stage == null || stage.isEmpty
          ? const {}
          : leadTabSelection(_leadStageKey(ref, stage));
      // `mine=1`: the signed-in user's own leads (owner or assignee) — what
      // the CRM Home cards count. Any other link is org-wide.
      ref.read(leadMineProvider.notifier).state = p['mine'] == '1';
      // The Business tab's Sales pipeline: every lead not converted and not
      // lost (the server's pipeline query set), point-in-time.
      // `owned=<user>`: leads the user OWNS (`lead_owner`, not assignee) —
      // what an Employee performance row counts.
      final owned = p['owned'] ?? '';
      ref.read(leadScopeParamsProvider.notifier).state = {
        if (p['pipeline'] == 'open') ...const {
          'status_type': 'new,in_progress,won,junk',
          'is_converted': 'false'
        },
        if (owned.isNotEmpty) 'lead_owner': owned,
      };
      final values = FilterValues();
      final source = p['source'];
      if (source != null && source.isNotEmpty) {
        values['sources'] = ChoiceValue(ids: {source});
      }
      final owner = p['owner'];
      if (owner != null && owner.isNotEmpty) {
        values['owners'] = ChoiceValue(ids: {owner});
      }
      final team = p['team'];
      if (team != null && team.isNotEmpty) {
        values['teams'] = ChoiceValue(ids: {team});
      }
      // A created-in window (`from` / `to`, YYYY-MM-DD): the Home's "this
      // period" figures count leads created in the period, so the list must
      // open on the same window or "My New leads 1" lands on 293.
      final from = DateTime.tryParse(p['from'] ?? '');
      final to = DateTime.tryParse(p['to'] ?? '');
      if (from != null || to != null) {
        values['created'] = DateValue(from: from, to: to);
      }
      _applyLeadFilters(ref, values);
    case Routes.payments:
      final mode = p['mode'] ?? '';
      if (mode == 'payments' || mode == 'invoices') {
        ref.read(payModeProvider.notifier).state = mode;
      }
      ref.read(payTabProvider.notifier).state = p['tab'] ?? 'all';
      // A payment-date window (the period a "collected" figure covers) and a
      // customer (a Top-5 outstanding / Top customers row), as drawer facets.
      final pv = FilterValues();
      final pFrom = DateTime.tryParse(p['from'] ?? '');
      final pTo = DateTime.tryParse(p['to'] ?? '');
      if (pFrom != null || pTo != null) {
        pv['paymentDate'] = DateValue(from: pFrom, to: pTo);
      }
      ref.read(paymentFiltersProvider.notifier).state = pv;
      ref.read(payCustomerProvider.notifier).state = p['cust'] ?? '';
    case Routes.followups:
      ref.read(followupTabProvider.notifier).state = p['tab'] ?? 'all';
      // A due-date window (the period a "missed" figure covers).
      ref.read(followupFiltersProvider.notifier).state =
          _windowFilters(p, 'due', mine: p['mine'] == '1');
    case Routes.tasks:
      ref.read(crmTaskTabProvider.notifier).state = p['tab'] ?? 'all';
      ref.read(crmTaskFiltersProvider.notifier).state =
          _windowFilters(p, 'due', mine: p['mine'] == '1');
    case Routes.quotes:
      final status = p['status'];
      ref.read(quoteTabProvider.notifier).state =
          status == null || status.isEmpty ? const {} : {status.toLowerCase()};
      // A created window (Quote acceptance is over the quotes of the period).
      ref.read(quoteFiltersProvider.notifier).state =
          _windowFilters(p, 'created');
  }
}

/// Drawer values holding just `from` / `to` as the [field] date facet, or
/// empty — a dashboard link always resets the drawer it lands on.
/// [mine] adds the signed-in user as the assignee facet (the lists key the
/// session user as `'me'`) — a Home card's own figure.
FilterValues _windowFilters(Map<String, String> p, String field,
    {bool mine = false}) {
  final values = FilterValues();
  if (mine) values['assignees'] = ChoiceValue(ids: const {'me'});
  final from = DateTime.tryParse(p['from'] ?? '');
  final to = DateTime.tryParse(p['to'] ?? '');
  if (from != null || to != null) values[field] = DateValue(from: from, to: to);
  return values;
}

/// The Leads chip key for a stage given as either its id or its key (the
/// funnel sends `lead_status_id`; the chips are keyed by `CatalogOption.key`).
String _leadStageKey(WidgetRef ref, String stage) {
  for (final s in ref.read(leadStatusesProvider)) {
    if (s.id == stage || s.key == stage) return s.key;
  }
  return stage;
}

/// Mirrors the Leads screen's own `_applyFilters`: the scoped fetch is keyed
/// by the encoded params, so the query must be dropped for the new filter to
/// reach the server.
void _applyLeadFilters(WidgetRef ref, FilterValues values) {
  final params = leadFilterParamsFor(values, ref.read(leadFilterCodecProvider));
  ref.invalidate(leadsScopedProvider(leadListQueryFor(params,
      archived: ref.read(leadArchivedProvider),
      mine: ref.read(leadMineProvider))));
  ref.read(leadFiltersProvider.notifier).state = values;
}

/// A Dashboard › CRM link to Leads, narrowed to what the tab's figures count:
/// leads created in the tab's period, within the picked team / member. The
/// cards are period figures ("New leads 1" is one lead created this month),
/// so the list must open on that window — not on every lead the role can see.
/// Keys the route already carries (an Employee row's `owner`) are kept.
String leadsLinkScoped(
  String route, {
  required String periodLabel,
  DateTimeRange? customRange,
  String team = 'all',
  String member = '',
  DateTime? today,
}) {
  final link = DashLink.parse(route);
  if (link.path != Routes.leads) return route;
  final q = Map<String, String>.from(link.params);
  final period =
      CrmPeriod.values.where((p) => p.label == periodLabel).firstOrNull;
  if (period != null && period != CrmPeriod.custom || customRange != null) {
    final r = crmPeriodRange(period ?? CrmPeriod.custom,
        custom: customRange, today: today);
    String d(DateTime t) =>
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    q.putIfAbsent('from', () => d(r.from));
    q.putIfAbsent('to', () => d(r.to));
  }
  if (member.isNotEmpty) q.putIfAbsent('owner', () => member);
  // 'all' / 'individual' are the picker's pseudo-teams, not team ids.
  if (team.isNotEmpty && team != 'all' && team != 'individual') {
    q.putIfAbsent('team', () => team);
  }
  return Uri(path: link.path, queryParameters: q).toString();
}

/// [leadsLinkScoped] from the Dashboard's live period / team / member.
String dashLeadsLink(WidgetRef ref, String route) => leadsLinkScoped(
      route,
      periodLabel: ref.read(dashPeriodProvider),
      customRange: ref.read(dashCustomRangeProvider),
      team: ref.read(dashTeamProvider),
      member: ref.read(dashMemberProvider),
    );

/// `period=1` on a card route means "the Dashboard's selected period": it is
/// replaced by the concrete `from` / `to` window the figure was computed for
/// (the Business tab's "Payments collected" is paid in the period).
String withDashPeriod(
  String route, {
  required String periodLabel,
  DateTimeRange? customRange,
  DateTime? today,
}) {
  final link = DashLink.parse(route);
  if (link.params['period'] != '1') return route;
  final q = Map<String, String>.from(link.params)..remove('period');
  final period =
      CrmPeriod.values.where((p) => p.label == periodLabel).firstOrNull;
  if (period != null && period != CrmPeriod.custom || customRange != null) {
    final r = crmPeriodRange(period ?? CrmPeriod.custom,
        custom: customRange, today: today);
    String d(DateTime t) =>
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    q['from'] = d(r.from);
    q['to'] = d(r.to);
  }
  return Uri(path: link.path, queryParameters: q).toString();
}

/// [withDashPeriod] from the Dashboard's live period.
String dashPeriodLink(WidgetRef ref, String route) => withDashPeriod(route,
    periodLabel: ref.read(dashPeriodProvider),
    customRange: ref.read(dashCustomRangeProvider));
