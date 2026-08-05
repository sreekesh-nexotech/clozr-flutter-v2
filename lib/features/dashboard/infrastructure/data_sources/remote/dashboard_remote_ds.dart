import 'package:flutter/widgets.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/app_error.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/dash_colors.dart';
import '../../../domain/entities/dashboard_models.dart';

/// Remote dashboard data: fires every widget endpoint of the four admin
/// dashboard groups concurrently and maps the JSON onto the existing
/// [DashboardData] bundle.
///
/// Resilience contract: each call is individually caught — a 403 (no
/// `view_dashboard` permission, or `scope=admin` without an admin role) or any
/// other failure nulls just that section, and [mapDashboard] then falls back to
/// the [base] value per section/field. In production [base] is
/// [DashboardData.empty] (zeros/empties — never fabricated figures), so an
/// unsupplied section stays honestly empty. A `scope=admin` 403 is retried once
/// with `scope=own` before giving up. Mapping is static so tests feed fixture
/// maps without an HTTP stack.
class DashboardRemoteDataSource {
  const DashboardRemoteDataSource(this._api);

  final ApiService _api;

  // ── section keys of the raw bundle (shared with the repository + tests) ──
  static const kCustomerKpis = 'customer_kpis';
  static const kReceivables = 'total_receivables';
  static const kTopCustomers = 'top_customers';
  static const kTeams = 'teams';
  static const kCrmKpis = 'crm_kpis';
  static const kCrmFunnel = 'crm_funnel';
  static const kCrmInflow = 'crm_inflow';
  static const kCrmMissed = 'crm_missed';
  static const kCrmSources = 'crm_sources';
  static const kCrmStuckLeads = 'crm_stuck_leads';
  static const kCrmStuckQuotes = 'crm_stuck_quotes';
  static const kCrmStuckPayments = 'crm_stuck_payments';
  static const kCrmStuckWonNc = 'crm_stuck_won_nc';
  static const kCrmEmployees = 'crm_employees';
  static const kPmoKpis = 'pmo_kpis';
  static const kPmoStatus = 'pmo_status';
  static const kPmoOverdue = 'pmo_overdue';
  static const kPmoProjects = 'pmo_projects';
  static const kPmoEmployees = 'pmo_employees';
  static const kIssueKpis = 'issue_kpis';
  static const kIssueStatus = 'issue_status';
  static const kIssueSla = 'issue_sla';
  static const kIssueAttention = 'issue_attention';
  static const kIssueFlow = 'issue_flow';
  static const kIssueEmployees = 'issue_employees';

  /// Fetches every dashboard section concurrently. Values are the decoded JSON
  /// bodies, or null when that call failed — never throws. Any [AppError]s
  /// caught along the way are appended to [errors] (when supplied) so the
  /// repository can surface a representative failure when *every* call failed.
  Future<Map<String, Object?>> fetchSections({
    String period = 'month',
    String? teamId,
    List<AppError>? errors,
  }) async {
    // 'all' is the org-wide sentinel and 'individual' is not a team uuid —
    // both mean "no team filter" for the widget endpoints.
    final team = (teamId == null || teamId.isEmpty || teamId == 'all' || teamId == 'individual')
        ? null
        : teamId;

    void note(Object err) {
      if (errors != null && err is AppError) errors.add(err);
    }

    Future<Object?> call(String path, [Map<String, dynamic>? extra]) async {
      Map<String, dynamic> query(String scope) => {
            'scope': scope,
            'period': period,
            if (team != null) 'team_id': team,
            ...?extra,
          };
      try {
        return await _api.get(path, query: query('admin'));
      } on AppError catch (e) {
        if (e.type == AppErrorType.forbidden) {
          // Admin scope needs an org-admin role — retry once as 'own' so a
          // non-admin with dashboard permission still sees their slice.
          try {
            return await _api.get(path, query: query('own'));
          } on Object catch (e2) {
            note(e2);
            return null;
          }
        }
        note(e);
        return null;
      } on Object catch (e) {
        note(e);
        return null;
      }
    }

    Future<Object?> fetchTeams() async {
      try {
        return await _api.get('${ApiEndpoints.dashboardNew}/teams/');
      } on Object {
        return null;
      }
    }

    const admin = ApiEndpoints.dashboardNew;
    const crm = ApiEndpoints.dashboardCrm;
    const pmo = ApiEndpoints.dashboardPmo;
    const issue = ApiEndpoints.dashboardIssue;

    // Building the map starts every future — the whole bundle is concurrent.
    final sections = <String, Future<Object?>>{
      kCustomerKpis: call('$admin/customer-kpis/'),
      kReceivables: call('$admin/total-receivables/'),
      kTopCustomers: call('$admin/top-customers/'),
      kTeams: fetchTeams(),
      kCrmKpis: call('$crm/kpis/'),
      kCrmFunnel: call('$crm/lead-funnel/'),
      kCrmInflow: call('$crm/lead-inflow-trend/'),
      kCrmMissed: call('$crm/missed/'),
      kCrmSources: call('$crm/lead-sources/'),
      kCrmStuckLeads: call('$crm/stuck-items/', {'kind': 'leads'}),
      kCrmStuckQuotes: call('$crm/stuck-items/', {'kind': 'quotes'}),
      kCrmStuckPayments: call('$crm/stuck-items/', {'kind': 'payments'}),
      kCrmStuckWonNc: call('$crm/stuck-items/', {'kind': 'won_nc'}),
      kCrmEmployees: call('$crm/employee-performance/'),
      kPmoKpis: call('$pmo/kpis/'),
      kPmoStatus: call('$pmo/project-status/'),
      kPmoOverdue: call('$pmo/overdue-tasks/'),
      kPmoProjects: call('$pmo/active-projects/'),
      kPmoEmployees: call('$pmo/employee-performance/'),
      kIssueKpis: call('$issue/kpis/'),
      kIssueStatus: call('$issue/tickets-by-status/'),
      kIssueSla: call('$issue/sla-priority-mix/'),
      kIssueAttention: call('$issue/top-tickets-needing-attention/'),
      kIssueFlow: call('$issue/ticket-flow-trend/'),
      kIssueEmployees: call('$issue/employee-performance/'),
    };

    final keys = sections.keys.toList();
    final values = await Future.wait(sections.values);
    return {for (var i = 0; i < keys.length; i++) keys[i]: values[i]};
  }

  // ── mapping (static, visible for tests) ──

  /// Builds a full [DashboardData] from the raw section bundle, taking [base]
  /// for every section/field a call failed to supply. In production [base] is
  /// [DashboardData.empty] so an unsupplied section stays empty (never mock);
  /// spark/figures are only ever those the API supplied.
  static DashboardData mapDashboard(Map<String, Object?> raw, DashboardData base) {
    final receivables = _receivables(raw[kReceivables], base);
    return DashboardData(
      adminKpis: _adminKpis(raw[kCustomerKpis], base.adminKpis),
      receivablesTotal: receivables.total,
      receivablesSub: receivables.sub,
      overdueTotal: receivables.overdueLabel,
      upcomingTotal: receivables.upcomingLabel,
      aging: receivables.aging,
      upcoming: receivables.upcoming,
      outstanding: _outstanding(raw[kTopCustomers], base.outstanding),
      outstandingTotal: _outstandingTotal(raw[kTopCustomers], base.outstandingTotal),
      topCustomers: _topCustomers(raw[kTopCustomers], base.topCustomers),
      crmKpis: _crmKpis(raw[kCrmKpis], base.crmKpis),
      crmFunnel: _funnel(raw[kCrmFunnel], base.crmFunnel),
      crmInflow: _trendOf(
        raw[kCrmInflow],
        base.crmInflow,
        aKeys: const ['new_leads', 'created'],
        bKeys: const ['won_leads', 'won'],
      ),
      crmAttention: _attention(raw[kCrmMissed], base.crmAttention),
      crmSources: _sources(raw[kCrmSources], base.crmSources),
      crmStuck: {
        'stale': _stuckRows(raw[kCrmStuckLeads], base.crmStuck['stale'] ?? const []),
        'quotes': _stuckRows(raw[kCrmStuckQuotes], base.crmStuck['quotes'] ?? const []),
        'payments': _stuckRows(raw[kCrmStuckPayments], base.crmStuck['payments'] ?? const []),
        'wonnc': _stuckRows(raw[kCrmStuckWonNc], base.crmStuck['wonnc'] ?? const []),
      },
      crmEmployees: _crmEmployees(raw[kCrmEmployees], base.crmEmployees),
      opsKpis: _opsKpis(raw[kPmoKpis], base.opsKpis),
      opsStatus: _donutParts(raw[kPmoStatus], base.opsStatus),
      opsOverdue: _opsOverdue(raw[kPmoOverdue], base.opsOverdue),
      opsProjects: _opsProjects(raw[kPmoProjects], base.opsProjects),
      opsRoster: _opsRoster(raw[kPmoEmployees], base.opsRoster),
      helpKpis: _helpKpis(raw[kIssueKpis], base.helpKpis),
      helpCategories: _helpCategories(raw[kIssueStatus], base.helpCategories),
      helpSla: _donutSection(raw[kIssueSla], 'sla', _slaBuckets, base.helpSla),
      helpPriority:
          _donutSection(raw[kIssueSla], 'priority', _priorityBuckets, base.helpPriority),
      helpAttention: _helpAttention(raw[kIssueAttention], base.helpAttention),
      helpFlow: _trendOf(
        raw[kIssueFlow],
        base.helpFlow,
        aKeys: const ['opened', 'new_tickets', 'created'],
        bKeys: const ['resolved', 'closed'],
      ),
      helpRoster: _helpRoster(raw[kIssueEmployees], base.helpRoster),
      teamOptions: _teamOptions(raw[kTeams], base.teamOptions),
    );
  }

  // ── KPI cards ──

  /// Copies a mock KPI card, swapping only value/unit/sub/trend (+ progress
  /// when the API value derives it). Icon, accent, label, spark and route are
  /// reused from the mock so the cards keep their look and navigation.
  static DashKpi _kpiWith(
    DashKpi b, {
    required String value,
    String? unit,
    String? sub,
    num? trendPct,
    bool goodWhenUp = true,
    double? progress,
  }) {
    final t = trendPct;
    return DashKpi(
      icon: b.icon,
      accent: b.accent,
      iconBg: b.iconBg,
      value: value,
      unit: unit ?? b.unit,
      label: b.label,
      sub: sub ?? b.sub,
      trendPositive: t == null ? b.trendPositive : (t == 0 || (t > 0) == goodWhenUp),
      trend: t == null ? b.trend : _signedPct(t),
      arrow: t == null
          ? b.arrow
          : (t > 0
              ? DashTrendArrow.up
              : t < 0
                  ? DashTrendArrow.down
                  : DashTrendArrow.flat),
      spark: b.spark,
      progress: progress ?? b.progress,
      route: b.route,
    );
  }

  /// `/dashboard-new/customer-kpis/` → the 4 Business cards.
  static List<DashKpi> _adminKpis(Object? json, List<DashKpi> base) {
    if (json is! Map || base.length < 4) return base;
    final out = List<DashKpi>.of(base);
    final pipeline = json['sales_pipeline'];
    if (pipeline is Map && pipeline['amount'] != null) {
      final parts = _moneyParts(parseAmount(pipeline['amount']));
      out[0] = _kpiWith(base[0],
          value: parts[0], unit: parts[1], trendPct: _numOf(pipeline['trend_pct']));
    }
    final collected = json['payments_collected'];
    if (collected is Map && collected['collected'] != null) {
      final parts = _moneyParts(parseAmount(collected['collected']));
      final expected = parseAmount(collected['expected']);
      out[1] = _kpiWith(base[1],
          value: parts[0],
          unit: parts[1],
          sub: expected > 0 ? 'Of ${formatInr(expected)} expected' : null,
          trendPct: _numOf(collected['trend_pct']));
    }
    final overdue = json['overdue_receivables'];
    if (overdue is Map && overdue['amount'] != null) {
      final parts = _moneyParts(parseAmount(overdue['amount']));
      final customers = _intOf(overdue['customer_count']);
      out[2] = _kpiWith(base[2],
          value: parts[0],
          unit: parts[1],
          sub: customers != null ? 'Across $customers customers' : null,
          trendPct: _numOf(overdue['trend_pct']),
          goodWhenUp: false);
    }
    final tickets = json['open_tickets'];
    if (tickets is Map && tickets['count'] != null) {
      out[3] = _kpiWith(base[3],
          value: '${_intOf(tickets['count']) ?? 0}',
          unit: '',
          trendPct: _numOf(tickets['trend_pct']),
          goodWhenUp: false);
    }
    return out;
  }

  /// `/dashboard-crm/kpis/` → the 4 CRM cards.
  static List<DashKpi> _crmKpis(Object? json, List<DashKpi> base) {
    if (json is! Map || base.length < 4) return base;
    final out = List<DashKpi>.of(base);
    final newLeads = json['new_leads'];
    if (newLeads is Map && newLeads['count'] != null) {
      out[0] = _kpiWith(base[0],
          value: '${_intOf(newLeads['count']) ?? 0}', trendPct: _numOf(newLeads['trend_pct']));
    }
    final winRate = json['win_rate'];
    if (winRate is Map && winRate['pct'] != null) {
      out[1] = _kpiWith(base[1],
          value: _trimNum(_numOf(winRate['pct']) ?? 0), trendPct: _numOf(winRate['trend_pct']));
    }
    final firstResponse = json['first_response'];
    if (firstResponse is Map && firstResponse['median_minutes'] != null) {
      out[2] = _kpiWith(base[2],
          value: _trimNum(_numOf(firstResponse['median_minutes']) ?? 0),
          trendPct: _numOf(firstResponse['trend_pct']),
          goodWhenUp: false);
    }
    final quoteAcceptance = json['quote_acceptance'];
    if (quoteAcceptance is Map && quoteAcceptance['pct'] != null) {
      final pct = _numOf(quoteAcceptance['pct']) ?? 0;
      out[3] = _kpiWith(base[3],
          value: _trimNum(pct),
          trendPct: _numOf(quoteAcceptance['trend_pct']),
          progress: (pct / 100).clamp(0.0, 1.0).toDouble());
    }
    return out;
  }

  /// `/dashboard-pmo/kpis/` → the 4 Operations cards.
  static List<DashKpi> _opsKpis(Object? json, List<DashKpi> base) {
    if (json is! Map || base.length < 4) return base;
    final out = List<DashKpi>.of(base);
    final active = json['active_projects'];
    if (active is Map && active['count'] != null) {
      out[0] = _kpiWith(base[0],
          value: '${_intOf(active['count']) ?? 0}', trendPct: _numOf(active['trend_pct']));
    }
    final overdueProjects = json['projects_overdue'];
    if (overdueProjects is Map && overdueProjects['count'] != null) {
      final count = _intOf(overdueProjects['count']) ?? 0;
      final total = _intOf(overdueProjects['total']);
      out[1] = _kpiWith(base[1],
          value: total != null ? '$count / $total' : '$count',
          trendPct: _numOf(overdueProjects['trend_pct']),
          goodWhenUp: false,
          progress: (total != null && total > 0)
              ? (count / total).clamp(0.0, 1.0).toDouble()
              : null);
    }
    final overdueTasks = json['tasks_overdue'];
    if (overdueTasks is Map && overdueTasks['count'] != null) {
      out[2] = _kpiWith(base[2],
          value: '${_intOf(overdueTasks['count']) ?? 0}',
          trendPct: _numOf(overdueTasks['trend_pct']),
          goodWhenUp: false);
    }
    final cycle = json['avg_project_cycle'];
    if (cycle is Map && cycle['days'] != null) {
      out[3] = _kpiWith(base[3],
          value: _trimNum(_numOf(cycle['days']) ?? 0),
          trendPct: _numOf(cycle['trend_pct']),
          goodWhenUp: false);
    }
    return out;
  }

  /// `/dashboard-issue/kpis/` → the 4 Helpdesk cards.
  ///
  /// Documented shape: `open_tickets.count`, `sla_breaches.count`,
  /// `avg_resolution.minutes`, `first_response.minutes` (+ a 5th `reopen_rate`
  /// this 4-card grid has no slot for). Each candidate key carries the factor
  /// that converts it into the card's own unit — `avg_resolution` arrives in
  /// **minutes** but the card reads in **hours**, so it is scaled by 1/60 while
  /// the legacy `hours` keys pass through untouched. Alternative names are kept
  /// as a tolerance for older deployments; a card whose value cannot be found
  /// keeps its base figure.
  static List<DashKpi> _helpKpis(Object? json, List<DashKpi> base) {
    if (json is! Map || base.length < 4) return base;
    final out = List<DashKpi>.of(base);
    void swap(int i, List<String> names, List<(String, double)> valueKeys) {
      for (final name in names) {
        final node = json[name];
        num? value;
        num? trend;
        if (node is num) {
          value = node;
        } else if (node is Map) {
          for (final (key, factor) in valueKeys) {
            final raw = _numOf(node[key]);
            if (raw != null) {
              value = raw * factor;
              break;
            }
          }
          trend = _numOf(node['trend_pct']);
        }
        if (value != null) {
          out[i] = _kpiWith(base[i],
              value: _trimNum(value), trendPct: trend, goodWhenUp: false);
          return;
        }
      }
    }

    const asIs = 1.0;
    const minToHour = 1 / 60;
    swap(0, const ['open_tickets', 'open'], const [('count', asIs), ('value', asIs)]);
    swap(1, const ['sla_breaches', 'breaches'], const [('count', asIs), ('value', asIs)]);
    swap(2, const ['avg_resolution', 'avg_resolution_hours', 'resolution'],
        const [('minutes', minToHour), ('hours', asIs), ('median_hours', asIs), ('value', asIs)]);
    swap(3, const ['first_response', 'first_response_minutes'],
        const [('minutes', asIs), ('median_minutes', asIs), ('value', asIs)]);
    return out;
  }

  // ── charts ──

  /// `/dashboard-crm/lead-funnel/` (`{crm:{stages:[...]}}`) → funnel bars.
  static List<DashBar> _funnel(Object? json, List<DashBar> base) {
    Object? stages;
    if (json is Map) {
      final crm = json['crm'];
      if (crm is Map) stages = crm['stages'];
      stages ??= json['stages'];
    }
    if (stages is! List) return base;
    final out = <DashBar>[];
    for (final row in stages) {
      if (row is! Map) continue;
      final name = _str(row['name']);
      if (name.isEmpty) continue;
      out.add(DashBar(_shortLabel(name), _intOf(row['count']) ?? 0));
    }
    return out;
  }

  /// `/dashboard-issue/tickets-by-status/` — undocumented; a list of
  /// `{name|label|status, count}` rows under a few likely keys, else mock.
  static List<DashBar> _helpCategories(Object? json, List<DashBar> base) {
    Object? rows;
    if (json is List) {
      rows = json;
    } else if (json is Map) {
      for (final key in const ['statuses', 'items', 'types', 'results']) {
        if (json[key] is List) {
          rows = json[key];
          break;
        }
      }
    }
    if (rows is! List) return base;
    final out = <DashBar>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final name = _str(row['name'] ?? row['label'] ?? row['status']);
      final count = _intOf(row['count'] ?? row['total']);
      if (name.isEmpty || count == null) continue;
      out.add(DashBar(_shortLabel(name), count));
    }
    return out.isEmpty ? base : out;
  }

  /// Two-series area trend from `{buckets:[{label, <a>, <b>}]}`.
  static DashTrend _trendOf(
    Object? json,
    DashTrend base, {
    required List<String> aKeys,
    required List<String> bKeys,
  }) {
    final buckets = json is Map ? json['buckets'] : json;
    if (buckets is! List || buckets.isEmpty) return base;
    final a = <double>[];
    final b = <double>[];
    final labels = <String>[];
    for (final row in buckets) {
      if (row is! Map) continue;
      num? av;
      num? bv;
      for (final key in aKeys) {
        av ??= _numOf(row[key]);
      }
      for (final key in bKeys) {
        bv ??= _numOf(row[key]);
      }
      if (av == null && bv == null) continue;
      a.add((av ?? 0).toDouble());
      b.add((bv ?? 0).toDouble());
      labels.add(_str(row['label']));
    }
    if (a.isEmpty) return base;
    var maxVal = 0.0;
    for (final v in a) {
      if (v > maxVal) maxVal = v;
    }
    for (final v in b) {
      if (v > maxVal) maxVal = v;
    }
    return DashTrend(
      seriesA: a,
      seriesB: b,
      min: 0,
      max: maxVal <= 0 ? 1 : (maxVal * 1.15).ceilToDouble(),
      axisLabels: _axisLabels(labels),
    );
  }

  /// Four evenly spread month-style axis labels ("Jan 2026" → "Jan").
  static List<String> _axisLabels(List<String> labels) {
    String monthOf(String label) {
      final t = label.trim();
      return t.length > 3 ? t.substring(0, 3) : t;
    }

    if (labels.length <= 4) return [for (final l in labels) monthOf(l)];
    final n = labels.length - 1;
    return [
      monthOf(labels[0]),
      monthOf(labels[n ~/ 3]),
      monthOf(labels[2 * n ~/ 3]),
      monthOf(labels[n]),
    ];
  }

  // ── donuts ──

  static List<DashDonutPart> _donutParts(Object? json, List<DashDonutPart> base) {
    Object? rows;
    if (json is List) {
      rows = json;
    } else if (json is Map) {
      for (final key in const ['statuses', 'items', 'results']) {
        if (json[key] is List) {
          rows = json[key];
          break;
        }
      }
    }
    if (rows is! List) return base;
    final out = <DashDonutPart>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final label = _str(row['name'] ?? row['label']);
      if (label.isEmpty) continue;
      final fallback =
          base.isNotEmpty ? base[out.length % base.length].color : DashColors.grey;
      out.add(DashDonutPart(label, _hexColor(row['color']) ?? fallback, _intOf(row['count']) ?? 0));
    }
    return out.isEmpty ? base : out;
  }

  /// SLA block buckets — fixed field → (label, colour), in render order.
  static const _slaBuckets = <(String, String, Color)>[
    ('within_sla', 'Within SLA', DashColors.green),
    ('at_risk', 'At Risk', DashColors.amber),
    ('breached', 'Breached', DashColors.red),
  ];

  /// Priority block buckets — colours come from [_priorityColor] so the donut
  /// and the attention-list priority pills stay in step.
  static final _priorityBuckets = <(String, String, Color)>[
    ('low', 'Low', _priorityColor('low')),
    ('medium', 'Medium', _priorityColor('medium')),
    ('high', 'High', _priorityColor('high')),
    ('critical', 'Critical', _priorityColor('critical')),
  ];

  /// `/dashboard-issue/sla-priority-mix/` → one donut per block.
  ///
  /// Each block is a **flat count object keyed by category** — `{"within_sla":
  /// 25, "at_risk": 4, "breached": 3}` — not the `{statuses:[{name, count}]}`
  /// row list the PMO status donut returns, so [_donutParts] cannot read it.
  /// The key set is fixed and documented, so [buckets] supplies the labels,
  /// colours and render order while the payload supplies only the counts.
  /// A block the API omitted falls back to [base].
  static List<DashDonutPart> _donutSection(
    Object? json,
    String key,
    List<(String, String, Color)> buckets,
    List<DashDonutPart> base,
  ) {
    if (json is! Map) return base;
    final block = json[key];
    if (block is! Map) return base;
    final out = <DashDonutPart>[];
    for (final (field, label, color) in buckets) {
      final count = _intOf(block[field]);
      if (count == null) continue;
      out.add(DashDonutPart(label, color, count));
    }
    return out.isEmpty ? base : out;
  }

  // ── attention / sources / stuck ──

  /// `/dashboard-crm/missed/` → the four Attention Needed cards (fixed order).
  static List<DashAttentionCard> _attention(Object? json, List<DashAttentionCard> base) {
    if (json is! Map || base.length < 4) return base;
    const keys = ['payments_missed', 'followups_missed', 'tasks_missed', 'lost_after_quote'];
    final out = List<DashAttentionCard>.of(base);
    for (var i = 0; i < keys.length; i++) {
      final node = json[keys[i]];
      if (node is! Map || node['count'] == null) continue;
      final trendPct = _numOf(node['trend_pct']) ?? 0;
      var direction = _str(node['direction']);
      if (direction.isEmpty) {
        // All four metrics are bad-when-up.
        direction = trendPct > 0 ? 'worsening' : (trendPct < 0 ? 'improving' : 'steady');
      }
      final improving = direction == 'improving';
      final steady = direction == 'steady';
      out[i] = DashAttentionCard(
        value: '${_intOf(node['count']) ?? 0}',
        label: base[i].label,
        delta: trendPct == 0 ? '0' : _signedPct(trendPct),
        arrow: trendPct > 0
            ? DashTrendArrow.up
            : trendPct < 0
                ? DashTrendArrow.down
                : DashTrendArrow.flat,
        positive: improving,
        neutral: steady,
        note: improving ? 'Improving' : (steady ? 'Steady' : 'Worsening'),
        noteColor: improving
            ? DashColors.green
            : steady
                ? DashColors.textMid
                : DashColors.red,
        route: base[i].route,
      );
    }
    return out;
  }

  /// `/dashboard-crm/lead-sources/` → Lead Sources rows. The API has no cycle
  /// metric, so that column renders an em dash.
  static List<DashSource> _sources(Object? json, List<DashSource> base) {
    final rows = json is Map ? json['sources'] : null;
    if (rows is! List) return base;
    final out = <DashSource>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final name = _str(row['name']);
      if (name.isEmpty) continue;
      out.add(DashSource(
        name: name,
        leads: _intOf(row['total_leads']) ?? 0,
        won: _intOf(row['won_leads']) ?? 0,
        pct: '${_trimNum(_numOf(row['win_pct']) ?? 0)}%',
        cycle: '—',
        closed: formatInr(parseAmount(row['won_amount'])),
        up: null,
      ));
    }
    return out;
  }

  /// `/dashboard-crm/stuck-items/?kind=…` → one Stuck Items tab. `value` is
  /// polymorphic: a money string/number is formatted, a priority name passes
  /// through verbatim.
  static List<DashStuckRow> _stuckRows(Object? json, List<DashStuckRow> base) {
    final items = json is Map ? json['items'] : null;
    if (items is! List) return base;
    final out = <DashStuckRow>[];
    for (final row in items) {
      if (row is! Map) continue;
      final title = _str(row['title']);
      if (title.isEmpty) continue;
      out.add(DashStuckRow(
        title,
        _ownerName(row['owner']),
        _valueLabel(row['value']),
        '${_intOf(row['stuck_days']) ?? 0}d',
      ));
    }
    return out;
  }

  static String _ownerName(Object? owner) {
    if (owner is String) return owner.trim();
    if (owner is Map) return _str(owner['name']);
    return '';
  }

  static String _valueLabel(Object? value) {
    if (value is num) return formatInr(value);
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed != null ? formatInr(parsed) : value;
    }
    return '';
  }

  // ── rosters ──

  /// `/dashboard-crm/employee-performance/` → CRM employee rows. Registers
  /// each user so names/initials resolve and maps the signed-in uuid to 'me'.
  static List<DashCrmEmployee> _crmEmployees(Object? json, List<DashCrmEmployee> base) {
    final rows = json is Map ? json['results'] : null;
    if (rows is! List) return base;
    final out = <DashCrmEmployee>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final userId = _str(row['user_id']);
      if (userId.isEmpty) continue;
      UserDirectory.register(userId: userId, fullName: _str(row['name'] ?? row['full_name']));
      out.add(DashCrmEmployee(
        UserDirectory.mapUserId(userId),
        _intOf(row['open_leads']) ?? 0,
        _intOf(row['won_leads']) ?? 0,
        formatInr(parseAmount(row['closed_amount'])),
        '${_intOf(row['first_response_median_minutes']) ?? 0} min',
        relativeTime(parseApiDate(row['last_active_at'])),
      ));
    }
    return out;
  }

  /// `/dashboard-pmo/employee-performance/` → Operations roster rows.
  static List<DashRosterRow> _opsRoster(Object? json, List<DashRosterRow> base) {
    final rows = json is Map ? json['results'] : null;
    if (rows is! List) return base;
    final out = <DashRosterRow>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final userId = _str(row['user_id']);
      if (userId.isEmpty) continue;
      UserDirectory.register(userId: userId, fullName: _str(row['name'] ?? row['full_name']));
      final projects = _intOf(row['active_projects']) ?? 0;
      final tasks = _intOf(row['open_tasks']) ?? 0;
      final overdue = _intOf(row['tasks_overdue']) ?? 0;
      out.add(DashRosterRow(
        UserDirectory.mapUserId(userId),
        '$projects ${projects == 1 ? 'project' : 'projects'} · '
            '$tasks open ${tasks == 1 ? 'task' : 'tasks'}',
        '$overdue overdue',
        overdue > 0,
      ));
    }
    return out;
  }

  /// `/dashboard-issue/employee-performance/` — undocumented; requires at
  /// least one recognizable count per row, else the section keeps its mock.
  static List<DashRosterRow> _helpRoster(Object? json, List<DashRosterRow> base) {
    final rows = json is Map ? json['results'] : (json is List ? json : null);
    if (rows is! List) return base;
    final out = <DashRosterRow>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final userId = _str(row['user_id']);
      if (userId.isEmpty) continue;
      final open = _intOf(row['open_tickets'] ?? row['open']);
      final resolved = _intOf(row['resolved_tickets'] ?? row['resolved']);
      final breaches = _intOf(row['sla_breaches'] ?? row['breaches']);
      if (open == null && resolved == null && breaches == null) continue;
      UserDirectory.register(userId: userId, fullName: _str(row['name'] ?? row['full_name']));
      final b = breaches ?? 0;
      out.add(DashRosterRow(
        UserDirectory.mapUserId(userId),
        '${open ?? 0} open · ${resolved ?? 0} resolved',
        '$b ${b == 1 ? 'breach' : 'breaches'}',
        b > 0,
      ));
    }
    return out.isEmpty ? base : out;
  }

  // ── receivables / customers ──

  static _Receivables _receivables(Object? json, DashboardData base) {
    if (json is! Map) {
      return _Receivables(base.receivablesTotal, base.receivablesSub, base.overdueTotal,
          base.upcomingTotal, base.aging, base.upcoming);
    }
    final overdue = json['overdue'];
    final upcoming = json['upcoming'];
    final overdueTotal = overdue is Map ? parseAmount(overdue['total_amount']) : 0.0;
    final upcomingTotal = upcoming is Map ? parseAmount(upcoming['total_amount']) : 0.0;

    final total = json['total_amount'] != null
        ? formatInr(parseAmount(json['total_amount']))
        : base.receivablesTotal;
    final sub = (overdue is Map && upcoming is Map)
        ? '${formatInr(overdueTotal)} overdue · ${formatInr(upcomingTotal)} upcoming'
        : base.receivablesSub;
    final overdueLabel =
        overdue is Map ? 'Overdue · ${formatInr(overdueTotal)}' : base.overdueTotal;
    final upcomingLabel =
        upcoming is Map ? 'Upcoming · ${formatInr(upcomingTotal)}' : base.upcomingTotal;

    var aging = base.aging;
    if (overdue is Map) {
      const bucketKeys = ['0_30', '31_60', '61_90', '90_plus'];
      const bucketLabels = ['0–30 days', '31–60 days', '61–90 days', '90+ days'];
      final rows = <DashAgingRow>[];
      for (var i = 0; i < bucketKeys.length; i++) {
        final bucket = overdue[bucketKeys[i]];
        if (bucket is! Map) continue;
        final amount = parseAmount(bucket['amount']);
        rows.add(DashAgingRow(
          bucketLabels[i],
          formatInr(amount),
          i < base.aging.length ? base.aging[i].color : DashColors.grey,
          overdueTotal > 0 ? (amount / overdueTotal * 100) : 0,
        ));
      }
      if (rows.isNotEmpty) aging = rows;
    }

    var upcomingRows = base.upcoming;
    if (upcoming is Map) {
      // Buckets are cumulative server-side (next_90 ⊇ next_30 ⊇ next_7);
      // the panel renders each bucket amount as sent, like the mock.
      const keys = ['today', 'next_7', 'next_30', 'next_90'];
      const labels = ['Due today', 'Due in 7 days', 'Due in 30 days', 'Due in 90 days'];
      final rows = <DashLabelAmt>[];
      for (var i = 0; i < keys.length; i++) {
        final bucket = upcoming[keys[i]];
        if (bucket is! Map) continue;
        rows.add(DashLabelAmt(labels[i], formatInr(parseAmount(bucket['amount']))));
      }
      if (rows.isNotEmpty) upcomingRows = rows;
    }

    return _Receivables(total, sub, overdueLabel, upcomingLabel, aging, upcomingRows);
  }

  /// `top_outstanding` → Top 5 outstanding rows; bar width is relative to the
  /// largest row, colors reuse the mock rows by index.
  static List<DashOutstanding> _outstanding(Object? json, List<DashOutstanding> base) {
    final rows = json is Map ? json['top_outstanding'] : null;
    if (rows is! List) return base;
    var maxAmount = 0.0;
    final parsed = <(String, int, double)>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final name = _str(row['name']);
      if (name.isEmpty) continue;
      final amount = parseAmount(row['outstanding_amount']);
      if (amount > maxAmount) maxAmount = amount;
      parsed.add((name, _intOf(row['oldest_overdue_days']) ?? 0, amount));
    }
    final out = <DashOutstanding>[];
    for (var i = 0; i < parsed.length; i++) {
      final (name, days, amount) = parsed[i];
      out.add(DashOutstanding(
        name,
        days,
        formatInr(amount),
        base.isNotEmpty ? base[i % base.length].barColor : DashColors.red,
        maxAmount > 0 ? (amount / maxAmount * 100) : 0,
      ));
    }
    return out;
  }

  static String _outstandingTotal(Object? json, String base) {
    final rows = json is Map ? json['top_outstanding'] : null;
    if (rows is! List || rows.isEmpty) return base;
    var sum = 0.0;
    for (final row in rows) {
      if (row is Map) sum += parseAmount(row['outstanding_amount']);
    }
    return formatInr(sum);
  }

  /// `top_by_value` → Top customers (₹ Value). The API carries no order/recency
  /// meta, so the sub renders an em dash.
  static List<DashTopCustomer> _topCustomers(Object? json, List<DashTopCustomer> base) {
    final rows = json is Map ? json['top_by_value'] : null;
    if (rows is! List) return base;
    final out = <DashTopCustomer>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final name = _str(row['name']);
      if (name.isEmpty) continue;
      out.add(DashTopCustomer(name, '—', formatInr(parseAmount(row['total_value']))));
    }
    return out;
  }

  // ── operations ──

  /// `/dashboard-pmo/overdue-tasks/` → Overdue Tasks rows.
  static List<DashOverdueTask> _opsOverdue(Object? json, List<DashOverdueTask> base) {
    final rows = json is Map ? json['tasks'] : null;
    if (rows is! List) return base;
    final out = <DashOverdueTask>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final title = _str(row['title']);
      if (title.isEmpty) continue;
      final project = row['project'];
      out.add(DashOverdueTask(
        title,
        project is Map ? _str(project['name']) : '',
        project is Map ? formatInr(parseAmount(project['value'])) : '',
        '${_intOf(row['days_overdue']) ?? 0}d overdue',
        Routes.opsTasks,
      ));
    }
    return out;
  }

  /// `/dashboard-pmo/active-projects/` → Active Projects rows.
  ///
  /// The panel's segment filter consumes the mock's tab vocabulary:
  /// "All active"/"Overdue" show `tab == 'active'` rows (overdue = negative
  /// days remaining), "At risk" shows `tab == 'onhold'` — so API `health` maps
  /// onto those values, not onto the segment ids themselves.
  static List<DashProjectRow> _opsProjects(Object? json, List<DashProjectRow> base) {
    final rows = json is Map ? json['results'] : null;
    if (rows is! List) return base;
    final out = <DashProjectRow>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final name = _str(row['name']);
      if (name.isEmpty) continue;
      final manager = row['manager'];
      final status = row['status'];
      final health = _str(row['health']);
      final statusName = status is Map ? _str(status['name']) : '';
      out.add(DashProjectRow(
        name,
        manager is Map ? _str(manager['name']) : '',
        formatInr(parseAmount(row['value'])),
        statusName.isNotEmpty
            ? statusName
            : (health == 'at_risk'
                ? 'At risk'
                : health == 'delayed'
                    ? 'Overdue'
                    : 'Active'),
        (status is Map ? _hexColor(status['color']) : null) ??
            (health == 'at_risk'
                ? DashColors.amber
                : health == 'delayed'
                    ? DashColors.red
                    : DashColors.green),
        _intOf(row['progress_pct']) ?? 0,
        _intOf(row['days_remaining']) ?? 0,
        health == 'at_risk' ? 'onhold' : 'active',
      ));
    }
    return out;
  }

  // ── helpdesk attention ──

  /// `/dashboard-issue/top-tickets-needing-attention/` — undocumented; rows
  /// must at least carry a subject/title to be trusted, else mock.
  static List<DashTicketAttn> _helpAttention(Object? json, List<DashTicketAttn> base) {
    Object? rows;
    if (json is List) {
      rows = json;
    } else if (json is Map) {
      for (final key in const ['tickets', 'items', 'results']) {
        if (json[key] is List) {
          rows = json[key];
          break;
        }
      }
    }
    if (rows is! List) return base;
    final out = <DashTicketAttn>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final subject = _str(row['subject'] ?? row['title']);
      if (subject.isEmpty) continue;
      final customer = row['customer'];
      final assigned = row['assigned_to'];
      final subParts = <String>[
        if (customer is Map) _str(customer['name']) else if (customer is String) customer.trim(),
        if (assigned is Map) _str(assigned['name']) else if (assigned is String) assigned.trim(),
      ].where((s) => s.isNotEmpty).toList();
      final priority = row['priority'];
      final priorityName = priority is Map ? _str(priority['name']) : _str(priority);
      out.add(DashTicketAttn(
        tid: _str(row['ticket_no'] ?? row['issue_no'] ?? row['code'] ?? row['id']),
        subject: subject,
        sub: subParts.join(' · '),
        slaLabel: _str(row['sla_label'] ?? row['sla']),
        breached: row['breached'] == true || row['sla_breached'] == true,
        paused: row['paused'] == true || row['on_hold'] == true,
        priority: priorityName,
        priorityColor: (priority is Map ? _hexColor(priority['color']) : null) ??
            _priorityColor(priorityName),
      ));
    }
    return out.isEmpty ? base : out;
  }

  static Color _priorityColor(String name) {
    switch (name.toLowerCase()) {
      // `critical` is the helpdesk API's top band; `urgent` is the CRM wording.
      case 'urgent':
      case 'critical':
        return DashColors.red;
      case 'high':
        return DashColors.amber;
      case 'medium':
        return DashColors.blue;
      case 'low':
        return DashColors.lowGrey;
    }
    return DashColors.grey;
  }

  // ── teams ──

  /// `/dashboard-new/teams/` → team picker options ('all' arrives as a
  /// sentinel row from the API — nothing is prepended client-side).
  static List<DashTeamOption> _teamOptions(Object? json, List<DashTeamOption> base) {
    final rows = json is Map ? json['items'] : null;
    if (rows is! List) return base;
    final out = <DashTeamOption>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final value = _str(row['value']);
      final label = _str(row['label']);
      if (value.isEmpty || label.isEmpty) continue;
      out.add(DashTeamOption(value, label, ''));
    }
    return out.isEmpty ? base : out;
  }

  // ── small parsers ──

  /// Splits a formatted amount into value + unit for the KPI cards
  /// (`₹18.4L` → `['₹18.4', 'L']`).
  static List<String> _moneyParts(num amount) {
    final s = formatInr(amount);
    for (final unit in const ['Cr', 'L', 'K']) {
      if (s.endsWith(unit)) return [s.substring(0, s.length - unit.length), unit];
    }
    return [s, ''];
  }

  /// `12.3` → `'+12.3%'`, `-8.0` → `'-8%'`, `0` → `'0%'`.
  static String _signedPct(num pct) {
    final t = _trimNum(pct);
    return pct > 0 ? '+$t%' : '$t%';
  }

  /// Rounds to one decimal and drops a trailing `.0`.
  static String _trimNum(num v) {
    final r = (v * 10).roundToDouble() / 10;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
  }

  static num? _numOf(Object? v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static int? _intOf(Object? v) => _numOf(v)?.round();

  static String _str(Object? v) {
    if (v is String) return v.trim();
    if (v is num) return _trimNum(v);
    return '';
  }

  /// Keeps short stage names whole and clamps long ones for the bar chart.
  static String _shortLabel(String name) {
    final label = name.trim();
    if (label.length <= 12) return label;
    final firstWord = label.split(' ').first;
    if (firstWord.length <= 12) return firstWord;
    return '${label.substring(0, 11)}…';
  }

  /// `'#RRGGBB'` (also `#RGB` / `#AARRGGBB`) → [Color]; null when unparseable.
  static Color? _hexColor(Object? v) {
    if (v is! String) return null;
    var hex = v.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }
}

/// The receivables panel's mapped fields, bundled so [DashboardRemoteDataSource]
/// can build them in one pass.
class _Receivables {
  const _Receivables(
      this.total, this.sub, this.overdueLabel, this.upcomingLabel, this.aging, this.upcoming);

  final String total;
  final String sub;
  final String overdueLabel;
  final String upcomingLabel;
  final List<DashAgingRow> aging;
  final List<DashLabelAmt> upcoming;
}
