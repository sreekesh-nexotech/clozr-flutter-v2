import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/app_error.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/crm_home_models.dart';

/// Remote data for the personal **CRM Home** dashboard. Fires the caller's
/// (`scope=own`) `dashboard-crm/*` widgets concurrently and maps the JSON onto
/// [CrmHomeData].
///
/// Resilience contract: each call is individually caught — a failure nulls just
/// that section, and [mapHome] falls back to the neutral empties for it (never
/// the mock literals). Any [AppError]s are collected into the optional sink so
/// the repository can surface a representative failure when every call failed.
///
/// The mappers are `static` and pure so tests feed fixture maps without an HTTP
/// stack. `my-recent-wins/` and `stuck-items/` shapes are only partly
/// documented, so those mappers probe several likely keys and drop to empty
/// (not mock) for anything unparseable.
class CrmHomeRemoteDataSource {
  const CrmHomeRemoteDataSource(this._api);

  final ApiService _api;

  // Section keys of the raw bundle (shared with the repository + tests).
  static const kKpis = 'kpis';
  static const kFunnel = 'funnel';
  static const kMissed = 'missed';
  static const kWins = 'wins';
  static const kStuckFu = 'stuck_fu';
  static const kStuckPay = 'stuck_pay';
  static const kStuckQuotes = 'stuck_quotes';
  static const kStuckNoProj = 'stuck_noproj';

  /// The overdue-module chip → stuck-items `kind`. "Follow ups" has no stuck
  /// kind of its own, so it approximates to stale `leads` (leads needing a
  /// follow-up); "Project not created" is `won_nc` (won lead, no project).
  static const _chipKinds = {
    'fu': 'leads',
    'pay': 'payments',
    'quotes': 'quotes',
    'noproj': 'won_nc',
  };

  /// Fetches every CRM Home section concurrently. Values are the decoded JSON
  /// bodies, or null when that call failed — never throws.
  Future<Map<String, Object?>> fetchSections({List<AppError>? errors}) async {
    void note(Object err) {
      if (errors != null && err is AppError) errors.add(err);
    }

    Future<Object?> call(String path, [Map<String, dynamic>? query]) async {
      try {
        return await _api.get(path, query: query);
      } on AppError catch (e) {
        note(e);
        return null;
      } on Object catch (e) {
        note(e);
        return null;
      }
    }

    const base = ApiEndpoints.dashboardCrm; // '/crm/dashboard-crm'
    const own = {'scope': 'own'};
    Map<String, dynamic> stuck(String kind) => {'scope': 'own', 'kind': kind};

    final sections = <String, Future<Object?>>{
      kKpis: call('$base/kpis/', own),
      kFunnel: call('$base/lead-funnel/', own),
      kMissed: call('$base/missed/', own),
      kWins: call('$base/my-recent-wins/'),
      kStuckFu: call('$base/stuck-items/', stuck(_chipKinds['fu']!)),
      kStuckPay: call('$base/stuck-items/', stuck(_chipKinds['pay']!)),
      kStuckQuotes: call('$base/stuck-items/', stuck(_chipKinds['quotes']!)),
      kStuckNoProj: call('$base/stuck-items/', stuck(_chipKinds['noproj']!)),
    };

    final keys = sections.keys.toList();
    final values = await Future.wait(sections.values);
    return {for (var i = 0; i < keys.length; i++) keys[i]: values[i]};
  }

  // ── mapping (static, pure, visible for tests) ──

  /// Builds the whole bundle. Unsupplied sections stay empty (never mock).
  static CrmHomeData mapHome(Map<String, Object?> raw) {
    final (kpis, firstResponse) = mapKpis(raw[kKpis]);
    final (wins, winsCount, winsTotal) = mapWins(raw[kWins]);
    return CrmHomeData(
      kpis: kpis,
      firstResponseMedianMinutes: firstResponse,
      funnel: mapFunnel(raw[kFunnel]),
      attention: mapMissed(raw[kMissed]),
      wins: wins,
      winsCount: winsCount,
      winsTotal: winsTotal,
      overdue: {
        'fu': mapStuck(raw[kStuckFu], 'fu'),
        'pay': mapStuck(raw[kStuckPay], 'pay'),
        'quotes': mapStuck(raw[kStuckQuotes], 'quotes'),
        'noproj': mapStuck(raw[kStuckNoProj], 'noproj'),
      },
    );
  }

  /// `/dashboard-crm/kpis/` → the four KPI cards (New leads, Win rate, Quote to
  /// cash, Quote acceptance) + the first-response median for the trend card.
  static (List<CrmKpiValue>, int?) mapKpis(Object? json) {
    final m = json is Map ? json : const <Object?, Object?>{};

    CrmKpiValue build(
      Object? node, {
      required String valueKey,
      bool goodWhenUp = true,
      String unit = '',
      bool progress = false,
    }) {
      if (node is! Map) return CrmKpiValue(value: '0', unit: unit);
      final raw = _numOf(node[valueKey]);
      if (raw == null) return CrmKpiValue(value: '0', unit: unit);
      final trendPct = _numOf(node['trend_pct']);
      String? trend;
      var trendUp = true;
      var arrowUp = true;
      if (trendPct != null) {
        trend = _signedPct(trendPct);
        arrowUp = trendPct >= 0;
        trendUp = trendPct == 0 ? true : ((trendPct > 0) == goodWhenUp);
      }
      return CrmKpiValue(
        value: _trimNum(raw),
        unit: unit,
        trend: trend,
        trendUp: trendUp,
        arrowUp: arrowUp,
        progress: progress ? (raw / 100).clamp(0.0, 1.0).toDouble() : null,
      );
    }

    final cards = <CrmKpiValue>[
      build(m['new_leads'], valueKey: 'count'),
      build(m['win_rate'], valueKey: 'pct', unit: '%'),
      build(m['quote_to_cash_days'], valueKey: 'median_days', unit: 'days', goodWhenUp: false),
      build(m['quote_acceptance'], valueKey: 'pct', unit: '%', progress: true),
    ];
    final fr = m['first_response'] is Map ? _intOf((m['first_response'] as Map)['median_minutes']) : null;
    return (cards, fr);
  }

  /// `/dashboard-crm/lead-funnel/` (`{crm:{stages:[…]}}`) → funnel bars, in the
  /// org's configured stage colours.
  static List<CrmFunnelBar> mapFunnel(Object? json) {
    Object? stages;
    if (json is Map) {
      final crm = json['crm'];
      if (crm is Map) stages = crm['stages'];
      stages ??= json['stages'];
    }
    if (stages is! List) return const [];
    final out = <CrmFunnelBar>[];
    for (final row in stages) {
      if (row is! Map) continue;
      final name = _str(row['name']);
      if (name.isEmpty) continue;
      final tabKey = _leadTabForStage(name);
      out.add(CrmFunnelBar(
        label: name,
        count: _intOf(row['count']) ?? 0,
        color: _hexColor(row['color']) ?? _fallbackStageColor(tabKey),
        tabKey: tabKey,
      ));
    }
    return out;
  }

  /// `/dashboard-crm/missed/` → the four Attention cards (fixed order).
  static List<CrmAttentionValue> mapMissed(Object? json) {
    final m = json is Map ? json : const <Object?, Object?>{};
    const keys = ['payments_missed', 'followups_missed', 'tasks_missed', 'lost_after_quote'];
    return [for (final k in keys) _attn(m[k])];
  }

  static CrmAttentionValue _attn(Object? node) {
    if (node is! Map || node['count'] == null) return CrmAttentionValue.empty;
    final count = _intOf(node['count']) ?? 0;
    final trendPct = _numOf(node['trend_pct']) ?? 0;
    var direction = _str(node['direction']).toLowerCase();
    if (direction.isEmpty) {
      // All four metrics are bad-when-up (missed / lost).
      direction = trendPct > 0 ? 'worsening' : (trendPct < 0 ? 'improving' : 'steady');
    }
    final improving = direction == 'improving';
    final steady = direction == 'steady';
    return CrmAttentionValue(
      value: '$count',
      delta: trendPct == 0 ? '0' : _signedPct(trendPct),
      up: improving,
      neutral: steady,
      note: improving ? 'Improving' : (steady ? 'Steady' : 'Worsening'),
      noteColor: improving ? AppColors.success : (steady ? AppColors.textMuted2 : AppColors.error),
    );
  }

  /// `/dashboard-crm/my-recent-wins/` → recent won deals. **Shape is
  /// undocumented** — rows are probed under a few likely keys; a row without a
  /// name is skipped, and the count/total are summed from the rows actually
  /// returned. Anything unparseable falls back to empty (never mock).
  static (List<WinRow>, int, double) mapWins(Object? json) {
    final rows = _rowsOf(json, const ['results', 'wins', 'items', 'data']);
    final out = <WinRow>[];
    var total = 0.0;
    for (final row in rows) {
      if (row is! Map) continue;
      final name = _nameOf(row, const ['name', 'customer_name', 'lead_name', 'title'],
          const ['customer', 'lead', 'account']);
      if (name.isEmpty) continue;
      final amount = parseAmount(
          row['amount'] ?? row['value'] ?? row['won_amount'] ?? row['total_amount'] ?? row['closed_amount']);
      total += amount;
      UserDirectory.registerJson(row['owner'] ?? row['user']);
      final (route, id) = _winRoute(row);
      out.add(WinRow(
        name: name,
        deal: _nameOf(row, const ['deal', 'product', 'description', 'project_name'], const ['project', 'product']),
        amt: formatInr(amount),
        when: _wonWhen(row),
        route: route,
        id: id,
      ));
    }
    return (out, out.length, total);
  }

  /// `/dashboard-crm/stuck-items/?kind=…` → one overdue-module chip. `value` is
  /// polymorphic (money string/number formatted, else passed through).
  static List<OverdueRow> mapStuck(Object? json, String chip) {
    final items = json is Map ? json['items'] : null;
    if (items is! List) return const [];
    final (route, _) = _stuckRoute(chip);
    final out = <OverdueRow>[];
    for (final row in items) {
      if (row is! Map) continue;
      final title = _str(row['title']);
      if (title.isEmpty) continue;
      final owner = row['owner'];
      if (owner is Map) UserDirectory.registerJson(owner);
      out.add(OverdueRow(
        name: title,
        sub: _ownerName(owner),
        amt: _valueLabel(row['value']),
        age: _ageLabel(_intOf(row['stuck_days']) ?? 0),
        route: route,
        id: _str(row['id']),
      ));
    }
    return out;
  }

  // ── nav helpers ──

  static (String, String) _winRoute(Map row) {
    final leadId = _str(row['lead_id']);
    if (leadId.isNotEmpty) return (Routes.leadDetail, leadId);
    final customerId = _str(row['customer_id']);
    if (customerId.isNotEmpty) return (Routes.customerDetail, customerId);
    final type = _str(row['type'] ?? row['record_type']).toLowerCase();
    final id = _str(row['id']);
    if (type.contains('customer')) return (Routes.customerDetail, id);
    return (Routes.leadDetail, id);
  }

  static (String, String) _stuckRoute(String chip) {
    switch (chip) {
      case 'pay':
        return (Routes.paymentDetail, '');
      case 'quotes':
        return (Routes.quoteDetail, '');
      case 'noproj':
        return (Routes.leadDetail, ''); // won lead, no project
      case 'fu':
      default:
        return (Routes.leadDetail, ''); // stale lead
    }
  }

  static String _leadTabForStage(String name) {
    final n = name.toLowerCase();
    if (n.contains('new')) return 'new';
    if (n.contains('qualif')) return 'qualified';
    if (n.contains('quote')) return 'quote';
    if (n.contains('negoti')) return 'negotiation';
    if (n.contains('won')) return 'won';
    if (n.contains('lost')) return 'lost';
    return 'all';
  }

  static Color _fallbackStageColor(String tabKey) {
    switch (tabKey) {
      case 'new':
        return AppColors.blueBright;
      case 'qualified':
        return AppColors.success;
      case 'quote':
        return AppColors.navy;
      case 'negotiation':
        return AppColors.warning;
      case 'won':
        return AppColors.pending;
      case 'lost':
        return AppColors.error;
    }
    return AppColors.navy;
  }

  // ── small parsers ──

  static List<Object?> _rowsOf(Object? json, List<String> keys) {
    if (json is List) return json;
    if (json is Map) {
      for (final k in keys) {
        if (json[k] is List) return json[k] as List;
      }
    }
    return const [];
  }

  /// First non-empty display name from flat keys, then nested `{name}`/string
  /// objects.
  static String _nameOf(Map row, List<String> flatKeys, List<String> nestedKeys) {
    for (final k in flatKeys) {
      final s = _str(row[k]);
      if (s.isNotEmpty) return s;
    }
    for (final k in nestedKeys) {
      final v = row[k];
      if (v is Map) {
        final s = _str(v['name']);
        if (s.isNotEmpty) return s;
      } else if (v is String && v.trim().isNotEmpty) {
        return v.trim();
      }
    }
    return '';
  }

  static final DateFormat _dayMonth = DateFormat('d MMM');

  static String _wonWhen(Map row) {
    final date =
        parseApiDate(row['won_at'] ?? row['closed_at'] ?? row['won_date'] ?? row['date'] ?? row['updated_at']);
    if (date == null) return 'Won';
    return 'Won ${_dayMonth.format(date.toLocal())}';
  }

  static String _ageLabel(int days) => '$days ${days == 1 ? 'day' : 'days'} ago';

  static String _ownerName(Object? owner) {
    if (owner is String) return owner.trim();
    if (owner is Map) return _str(owner['name'] ?? owner['full_name']);
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

  static String _signedPct(num pct) {
    final t = _trimNum(pct);
    return pct > 0 ? '+$t%' : '$t%';
  }

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
