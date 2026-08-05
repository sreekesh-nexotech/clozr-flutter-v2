import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// View models for the CRM Home ("My" CRM) dashboard.
///
/// In API mode the screen renders from a [CrmHomeData] built by the CRM home
/// mappers off the `dashboard-crm/*` endpoints; a section the backend didn't
/// supply falls back to the neutral empties here — **never** to the mock
/// literals. In mock mode the screen keeps rendering the const literals in
/// `crm_home_providers.dart` unchanged.

/// A "recent win" row on the CRM Home dashboard.
class WinRow {
  final String name;
  final String deal;
  final String amt;
  final String when;

  /// Detail route to open + the record id (`?id=`).
  final String route;
  final String id;

  const WinRow({
    required this.name,
    required this.deal,
    required this.amt,
    required this.when,
    required this.route,
    required this.id,
  });
}

/// An "overdue item" row on the CRM Home dashboard.
class OverdueRow {
  final String name;
  final String sub;
  final String amt;
  final String age;
  final String route;
  final String id;

  const OverdueRow({
    required this.name,
    required this.sub,
    required this.amt,
    required this.age,
    required this.route,
    required this.id,
  });
}

/// One KPI card's *values* (the card's icon/label/route chrome stays fixed in
/// the screen). Trend colour ([trendUp]) is decoupled from the arrow glyph
/// ([arrowUp]) since some metrics rise while worsening.
class CrmKpiValue {
  final String value;
  final String unit;
  final String? trend; // null → no trend pill
  final bool trendUp; // pill colour: green (good) vs red (bad)
  final bool arrowUp; // glyph direction, decoupled from colour
  final double? progress; // 0..1 → progress bar instead of a sparkline

  const CrmKpiValue({
    required this.value,
    this.unit = '',
    this.trend,
    this.trendUp = true,
    this.arrowUp = true,
    this.progress,
  });

  /// Neutral empty card (zero value, no trend) — the honest fallback when the
  /// KPI endpoint didn't supply this metric.
  static const empty = CrmKpiValue(value: '0');
}

/// One lead-funnel bar. [color] is the org's configured stage colour (parsed
/// from the API hex) and [tabKey] drives the Leads drill-down.
class CrmFunnelBar {
  final String label;
  final int count;
  final Color color;
  final String tabKey;

  const CrmFunnelBar({
    required this.label,
    required this.count,
    required this.color,
    required this.tabKey,
  });
}

/// One "Attention needed" card's values. [up] = improving (green, down glyph),
/// [neutral] = steady (grey), else worsening (red, up glyph).
class CrmAttentionValue {
  final String value;
  final String delta;
  final bool up;
  final bool neutral;
  final String note;
  final Color noteColor;

  const CrmAttentionValue({
    required this.value,
    required this.delta,
    required this.up,
    required this.neutral,
    required this.note,
    required this.noteColor,
  });

  static const empty = CrmAttentionValue(
    value: '0',
    delta: '',
    up: false,
    neutral: true,
    note: '',
    noteColor: AppColors.textMuted2,
  );
}

/// The whole CRM Home bundle the screen renders in API mode.
class CrmHomeData {
  /// Fixed order: New leads, Win rate, Quote to cash, Quote acceptance.
  final List<CrmKpiValue> kpis;

  /// First-response median (minutes) for the trend card's headline. Null when
  /// the API didn't supply it. There is **no** first-response *series* endpoint,
  /// so the card shows the headline only — never a fabricated sparkline.
  final int? firstResponseMedianMinutes;

  final List<CrmFunnelBar> funnel;

  /// Fixed order: Payments missed, Followups missed, Tasks missed, Lost after quote.
  final List<CrmAttentionValue> attention;

  final List<WinRow> wins;
  final int winsCount;
  final double winsTotal;

  /// Overdue items keyed by chip: `fu` | `pay` | `quotes` | `noproj`.
  final Map<String, List<OverdueRow>> overdue;

  const CrmHomeData({
    required this.kpis,
    required this.firstResponseMedianMinutes,
    required this.funnel,
    required this.attention,
    required this.wins,
    required this.winsCount,
    required this.winsTotal,
    required this.overdue,
  });

  /// Neutral, data-free bundle: the API-mode base and per-section fallback.
  factory CrmHomeData.empty() => const CrmHomeData(
        kpis: [CrmKpiValue.empty, CrmKpiValue.empty, CrmKpiValue.empty, CrmKpiValue.empty],
        firstResponseMedianMinutes: null,
        funnel: [],
        attention: [
          CrmAttentionValue.empty,
          CrmAttentionValue.empty,
          CrmAttentionValue.empty,
          CrmAttentionValue.empty,
        ],
        wins: [],
        winsCount: 0,
        winsTotal: 0,
        overdue: {'fu': [], 'pay': [], 'quotes': [], 'noproj': []},
      );
}
