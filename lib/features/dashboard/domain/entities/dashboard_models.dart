import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import 'dash_colors.dart';

/// Immutable value types for the manager/admin dashboard panels. These mirror
/// the prototype's dashboard view-models (`dmKpis`, `moKpis`, `mhKpis`, …) so
/// the mock data source maps directly and the panels stay pure-render.

enum DashTrendArrow { up, down, flat }

/// A dashboard KPI card (2×2 grid). Renders a sparkline when [spark] is set, or
/// a progress bar when [progress] (0..1) is set.
class DashKpi {
  final IconData icon;
  final Color accent;
  final Color iconBg;
  final String value;
  final String unit;
  final String label;
  final String sub;
  final bool trendPositive; // green when true, red when false
  final String trend;
  final DashTrendArrow arrow;
  final List<double>? spark;
  final double? progress; // 0..1 → progress bar instead of sparkline
  final String route; // navigation target (context.go)

  const DashKpi({
    required this.icon,
    required this.accent,
    required this.iconBg,
    required this.value,
    required this.unit,
    required this.label,
    required this.sub,
    required this.trendPositive,
    required this.trend,
    this.arrow = DashTrendArrow.up,
    this.spark,
    this.progress,
    required this.route,
  });
}

/// A vertical bar in the Lead Funnel / Tickets-by-Category charts.
class DashBar {
  final String label;
  final int count;

  /// The record id behind the bar (a lead status key, an issue type id) when
  /// the source carries one — a tap opens the list filtered to it. Empty when
  /// the bar is a roll-up ("Other", "No category").
  final String id;
  const DashBar(this.label, this.count, {this.id = ''});
}

/// One arc of a donut chart (project status, SLA, priority mix).
class DashDonutPart {
  final String label;
  final Color color;
  final int count;

  /// The id the slice stands for (a project status id), when the source
  /// carries one; empty otherwise.
  final String id;
  const DashDonutPart(this.label, this.color, this.count, {this.id = ''});
}

/// A two-series area trend (Lead Inflow, Ticket Flow).
class DashTrend {
  final List<double> seriesA; // e.g. created / opened
  final List<double> seriesB; // e.g. won / resolved
  final double min;
  final double max;
  final List<String> axisLabels;

  /// The year the buckets cover ("2026") when the server sent month labels
  /// like "Jan 2026"; empty otherwise. These feeds are a fixed calendar year,
  /// so the card says so instead of implying the Period chip drives them.
  final String year;
  const DashTrend({
    required this.seriesA,
    required this.seriesB,
    required this.min,
    required this.max,
    required this.axisLabels,
    this.year = '',
  });
}

/// A receivables aging bracket (admin panel).
class DashAgingRow {
  final String label;
  final String amt;
  final Color color;
  final double pct; // 0..100 (segment width)
  const DashAgingRow(this.label, this.amt, this.color, this.pct);
}

/// A simple label + amount pair (upcoming receivables).
class DashLabelAmt {
  final String label;
  final String amt;
  const DashLabelAmt(this.label, this.amt);
}

/// A top-outstanding customer row (admin panel).
class DashOutstanding {
  final String name;
  final int days;
  final String amt;
  final Color barColor;
  final double pct; // 0..100

  /// The customer id, so the row can open the customer; empty when unknown.
  final String id;
  const DashOutstanding(this.name, this.days, this.amt, this.barColor, this.pct,
      {this.id = ''});
}

/// A top-customer row (admin panel).
class DashTopCustomer {
  final String name;
  final String sub;
  final String amt;

  /// The customer id, so the row can open the customer; empty when unknown.
  final String id;
  const DashTopCustomer(this.name, this.sub, this.amt, {this.id = ''});
}

/// A CRM "Attention Needed" 2×2 card.
class DashAttentionCard {
  final String value;
  final String label;
  final String delta;
  final DashTrendArrow arrow;
  final bool positive; // green vs red delta pill
  final bool neutral; // grey steady pill
  final String note;
  final Color noteColor;
  final String route;
  const DashAttentionCard({
    required this.value,
    required this.label,
    required this.delta,
    required this.arrow,
    required this.positive,
    required this.neutral,
    required this.note,
    required this.noteColor,
    required this.route,
  });
}

/// A CRM Lead Sources row.
class DashSource {
  final String name;
  final int leads;
  final int won;
  final String pct; // "12%"
  final String cycle; // "18d"
  final String closed; // "₹12.4L"
  final bool? up; // null → no trend badge

  /// The lead-source id, so a row can open Leads filtered to it.
  final String id;

  const DashSource({
    this.id = '',
    required this.name,
    required this.leads,
    required this.won,
    required this.pct,
    required this.cycle,
    required this.closed,
    required this.up,
  });

  String get metaLine => '$leads leads · $won won · $pct win · $cycle cycle';
}

/// A CRM "Stuck Items" row (also reused for admin-style rows).
class DashStuckRow {
  final String name;
  final String sub;
  final String amt;
  final String age;

  /// The record this row stands for (`/leads/detail?id=…`, a quote or a
  /// payment instalment), or null when the API sent no id.
  final String? route;
  const DashStuckRow(this.name, this.sub, this.amt, this.age, [this.route]);
}

/// A CRM employee-performance row.
class DashCrmEmployee {
  final String rid;
  final int active;
  final int won;
  final String closed; // "₹12.4L"
  final String ftr; // "22 min"
  final String last; // "2 m ago"
  /// The member's own user id (the raw uuid, where [rid] may read `'me'`).
  final String userId;

  const DashCrmEmployee(
      this.rid, this.active, this.won, this.closed, this.ftr, this.last,
      {this.userId = ''});

  String get metaLine => '$active active · $won won · $ftr first response';
}

/// An Operations overdue-task row.
class DashOverdueTask {
  final String title;
  final String sub;
  final String value; // project cost e.g. "₹36.5L"
  final String overdue; // "9d overdue"
  final String route;
  const DashOverdueTask(
      this.title, this.sub, this.value, this.overdue, this.route);
}

/// An Operations active-project row.
class DashProjectRow {
  final String name;
  final String owner;
  final String value;
  final String statusLabel;
  final Color statusColor;
  final int progress; // 0..100
  final int days; // negative = overdue
  final String tab; // 'all' | 'risk' | 'overdue' — which segment shows it
  /// The project id, so the row can open the project; empty when unknown.
  final String id;

  const DashProjectRow(this.name, this.owner, this.value, this.statusLabel,
      this.statusColor, this.progress, this.days, this.tab,
      {this.id = ''});
}

/// A roster row (Operations / Helpdesk employee performance).
class DashRosterRow {
  final String rid;
  final String sub;
  final String chipLabel;
  final bool chipBad; // red vs green chip
  /// The member's own user id (the raw uuid, where [rid] may read `'me'`).
  final String userId;

  const DashRosterRow(this.rid, this.sub, this.chipLabel, this.chipBad,
      {this.userId = ''});
}

/// A Helpdesk "Tickets Needing Attention" row.
class DashTicketAttn {
  final String tid;
  final String subject;
  final String sub;
  final String slaLabel;
  final bool breached;
  final bool paused;
  final String priority;
  final Color priorityColor;

  /// The ticket's `issue_id`, so the row can open the ticket; empty when the
  /// row did not carry one.
  final String issueId;

  const DashTicketAttn({
    this.issueId = '',
    required this.tid,
    required this.subject,
    required this.sub,
    required this.slaLabel,
    required this.breached,
    required this.paused,
    required this.priority,
    required this.priorityColor,
  });
}

/// A team option for the team picker sheet.
class DashTeamOption {
  final String id;
  final String name;
  final String sub;
  const DashTeamOption(this.id, this.name, this.sub);
}

/// The Team and Member dropdown options of one dashboard module, as the server
/// scopes them to the caller. [teamMembers] maps a team id to its member ids.
class DashFilterOptions {
  final List<DashTeamOption> teams;
  final List<DashTeamOption> users;
  final Map<String, List<String>> teamMembers;
  const DashFilterOptions(this.teams, this.users, this.teamMembers);

  /// The users of [teamId], or everyone for `all` / an unknown team.
  List<DashTeamOption> membersOf(String teamId) {
    final ids = teamMembers[teamId];
    if (ids == null) return users;
    return [
      for (final u in users)
        if (ids.contains(u.id)) u,
    ];
  }
}

/// The four-panel dashboard bundle returned by the repository.
class DashboardData {
  // Business / admin
  final List<DashKpi> adminKpis;
  final String receivablesTotal;
  final String receivablesSub;
  final String overdueTotal;
  final String upcomingTotal;
  final List<DashAgingRow> aging;
  final List<DashLabelAmt> upcoming;
  final List<DashOutstanding> outstanding;
  final String outstandingTotal;
  final List<DashTopCustomer> topCustomers;

  // CRM
  final List<DashKpi> crmKpis;
  final List<DashBar> crmFunnel;
  final DashTrend crmInflow;
  final List<DashAttentionCard> crmAttention;
  final List<DashSource> crmSources;
  final Map<String, List<DashStuckRow>> crmStuck; // keyed by chip
  final List<DashCrmEmployee> crmEmployees;

  // Operations
  final List<DashKpi> opsKpis;
  final List<DashDonutPart> opsStatus;
  final List<DashOverdueTask> opsOverdue;
  final List<DashProjectRow> opsProjects;
  final List<DashRosterRow> opsRoster;

  // Helpdesk
  final List<DashKpi> helpKpis;
  final List<DashBar> helpCategories;
  final List<DashDonutPart> helpSla;
  final List<DashDonutPart> helpPriority;
  final List<DashTicketAttn> helpAttention;
  final DashTrend helpFlow;
  final List<DashRosterRow> helpRoster;

  // Scope
  final List<DashTeamOption> teamOptions;

  const DashboardData({
    required this.adminKpis,
    required this.receivablesTotal,
    required this.receivablesSub,
    required this.overdueTotal,
    required this.upcomingTotal,
    required this.aging,
    required this.upcoming,
    required this.outstanding,
    required this.outstandingTotal,
    required this.topCustomers,
    required this.crmKpis,
    required this.crmFunnel,
    required this.crmInflow,
    required this.crmAttention,
    required this.crmSources,
    required this.crmStuck,
    required this.crmEmployees,
    required this.opsKpis,
    required this.opsStatus,
    required this.opsOverdue,
    required this.opsProjects,
    required this.opsRoster,
    required this.helpKpis,
    required this.helpCategories,
    required this.helpSla,
    required this.helpPriority,
    required this.helpAttention,
    required this.helpFlow,
    required this.helpRoster,
    required this.teamOptions,
  });

  /// A neutral, **data-free** bundle: the API-mode base and per-section
  /// fallback that replaces the mock bundle. It carries only design-token
  /// *chrome* — KPI card icons/accents/backgrounds/labels/routes, the fixed
  /// units and static captions, and the always-present "All teams" scope — with
  /// every figure zeroed, every list empty and every sparkline dropped.
  ///
  /// This is what makes API mode honest: a section the backend didn't supply
  /// (a failed or forbidden call) stays visibly empty instead of falling back
  /// to fabricated mock numbers. A genuinely empty org renders these same zeros.
  factory DashboardData.empty() {
    DashKpi kpi({
      required IconData icon,
      required Color accent,
      required Color iconBg,
      required String label,
      required String route,
      String unit = '',
      String sub = '',
    }) =>
        DashKpi(
          icon: icon,
          accent: accent,
          iconBg: iconBg,
          value: '0',
          unit: unit,
          label: label,
          sub: sub,
          trendPositive: true,
          trend: '',
          arrow: DashTrendArrow.flat,
          route: route,
        );

    DashAttentionCard attn(String label, String route) => DashAttentionCard(
          value: '0',
          label: label,
          delta: '',
          arrow: DashTrendArrow.flat,
          positive: false,
          neutral: true,
          note: '',
          noteColor: DashColors.textMid,
          route: route,
        );

    const emptyTrend =
        DashTrend(seriesA: [], seriesB: [], min: 0, max: 1, axisLabels: []);

    return DashboardData(
      // ── Business / admin ──
      adminKpis: [
        kpi(
            icon: PhosphorIconsFill.trendUp,
            accent: DashColors.green,
            iconBg: DashColors.tintGreen,
            label: 'Sales pipeline',
            sub: 'Pipeline value, all stages',
            // The open pipeline: every lead not yet won or lost.
            route: '${Routes.leads}?pipeline=open'),
        kpi(
            icon: PhosphorIconsFill.wallet,
            accent: DashColors.blue,
            iconBg: DashColors.tintBlue,
            label: 'Payments collected',
            // Payment plans that are paid — what the card counts.
            // …paid in the Dashboard's period (`period=1` → from / to).
            route: '${Routes.payments}?mode=payments&tab=paid&period=1'),
        kpi(
            icon: PhosphorIconsFill.warningCircle,
            accent: DashColors.red,
            iconBg: DashColors.tintRed,
            label: 'Overdue receivables',
            route: '${Routes.payments}?mode=payments&tab=overdue'),
        kpi(
            icon: PhosphorIconsFill.ticket,
            accent: DashColors.amber,
            iconBg: DashColors.tintAmber,
            label: 'Open tickets',
            sub: 'Across all priorities',
            // Every ticket that is not resolved — what the count is.
            route: '${Routes.tickets}?all=1&open=1'),
      ],
      receivablesTotal: '₹0',
      receivablesSub: '',
      overdueTotal: 'Overdue · ₹0',
      upcomingTotal: 'Upcoming · ₹0',
      aging: const [],
      upcoming: const [],
      outstanding: const [],
      outstandingTotal: '₹0',
      topCustomers: const [],
      // ── CRM ──
      crmKpis: [
        kpi(
            icon: PhosphorIconsFill.userPlus,
            accent: DashColors.green,
            iconBg: DashColors.tintGreen,
            label: 'New leads',
            sub: 'This period, all sources',
            route: Routes.leads),
        kpi(
            icon: PhosphorIconsFill.target,
            accent: DashColors.green,
            iconBg: DashColors.tintGreen,
            label: 'Win rate',
            unit: '%',
            sub: 'Won / qualified ratio',
            // The won leads the ratio is made of.
            route: '${Routes.leads}?group=won'),
        kpi(
            icon: PhosphorIconsFill.clockCountdown,
            accent: DashColors.red,
            iconBg: DashColors.tintRed,
            label: 'First to response',
            unit: 'minutes',
            sub: 'Initial engagement time',
            route: Routes.followups),
        kpi(
            icon: PhosphorIconsFill.fileText,
            accent: DashColors.blue,
            iconBg: DashColors.tintBlue,
            label: 'Quote acceptance',
            unit: '%',
            sub: 'Conversion rate',
            // Accepted among the quotes created in the period.
            route: '${Routes.quotes}?status=accepted&period=1'),
      ],
      crmFunnel: const [],
      crmInflow: emptyTrend,
      crmAttention: [
        // Each card counts a slice, so its tap lands on that slice (the
        // list screens read these — see `dashGo`).
        // …due in the Dashboard's period (`period=1` → from / to).
        attn('Payments missed',
            '${Routes.payments}?mode=payments&tab=overdue&period=1'),
        attn('Followups missed', '${Routes.followups}?tab=overdue&period=1'),
        attn('Tasks missed', '${Routes.tasks}?tab=overdue&period=1'),
        attn('Lost after quote', '${Routes.leads}?group=lost'),
      ],
      crmSources: const [],
      crmStuck: const {'stale': [], 'quotes': [], 'payments': [], 'wonnc': []},
      crmEmployees: const [],
      // ── Operations ──
      opsKpis: [
        kpi(
            icon: PhosphorIconsFill.briefcase,
            accent: DashColors.green,
            iconBg: DashColors.tintGreen,
            label: 'Active Projects',
            sub: 'In delivery right now',
            // Open (not closed) projects — what the count is.
            route: '${Routes.opsProjects}?group=open'),
        // A KPI that counts a *slice* of a list links to that slice, not the
        // whole list: the tap on "3 tasks overdue" must land on those three.
        // The target screens read these query params on entry.
        kpi(
            icon: PhosphorIconsFill.flag,
            accent: DashColors.red,
            iconBg: DashColors.tintRed,
            label: 'Projects Overdue',
            sub: 'Past their end date',
            // …among the open ones (a closed project is never overdue here).
            route: '${Routes.opsProjects}?end=overdue&group=open'),
        kpi(
            icon: PhosphorIconsFill.listChecks,
            accent: DashColors.red,
            iconBg: DashColors.tintRed,
            label: 'Tasks Overdue',
            sub: 'Across all projects',
            route: '${Routes.opsTasks}?due=overdue'),
        kpi(
            icon: PhosphorIconsFill.clock,
            accent: DashColors.red,
            iconBg: DashColors.tintRed,
            label: 'Avg Project Cycle',
            unit: 'days',
            sub: 'Start to handover',
            route: Routes.opsProjects),
        // The webapp's fifth card (`avg_task_cycle`): start → done for tasks.
        kpi(
            icon: PhosphorIconsFill.gauge,
            accent: DashColors.red,
            iconBg: DashColors.tintRed,
            label: 'Avg Task Cycle',
            unit: 'days',
            sub: 'Start to done',
            route: Routes.opsTasks),
      ],
      opsStatus: const [],
      opsOverdue: const [],
      opsProjects: const [],
      opsRoster: const [],
      // ── Helpdesk ──
      helpKpis: [
        kpi(
            icon: PhosphorIconsFill.ticket,
            accent: DashColors.blue,
            iconBg: DashColors.tintBlue,
            label: 'Open Tickets',
            sub: 'New, open & pending',
            route: '${Routes.tickets}?all=1&open=1'),
        kpi(
            icon: PhosphorIconsFill.warningCircle,
            accent: DashColors.red,
            iconBg: DashColors.tintRed,
            // Breached among the tickets created in the period.
            label: 'SLA Breaches',
            sub: 'Response or resolution',
            route: '${Routes.tickets}?all=1&breaching=1&period=1'),
        kpi(
            icon: PhosphorIconsFill.timer,
            accent: DashColors.green,
            iconBg: DashColors.tintGreen,
            label: 'Avg Resolution',
            unit: 'hours',
            sub: 'Median, this period',
            route: '${Routes.tickets}?all=1'),
        kpi(
            icon: PhosphorIconsFill.lightning,
            accent: DashColors.green,
            iconBg: DashColors.tintGreen,
            label: 'First Response',
            unit: 'min',
            sub: 'Median, this period',
            route: '${Routes.tickets}?all=1'),
      ],
      helpCategories: const [],
      helpSla: const [],
      helpPriority: const [],
      helpAttention: const [],
      helpFlow: emptyTrend,
      helpRoster: const [],
      // ── Scope ──
      teamOptions: const [DashTeamOption('all', 'All teams', '')],
    );
  }
}
