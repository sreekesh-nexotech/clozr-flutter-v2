import 'package:equatable/equatable.dart';

/// One Helpdesk KPI figure: a count, or a duration the card renders in its own
/// unit, plus the period-over-period trend behind its chip.
///
/// [trendPct] is null when the server sent none, which the card reads as "show
/// no chip" — a missing trend is not a flat one.
class HelpKpi extends Equatable {
  const HelpKpi({this.count, this.minutes, this.pct, this.trendPct});

  final int? count;

  /// `avg_resolution` and `first_response` both arrive in **minutes**; the
  /// cards read in days and hours respectively.
  final int? minutes;
  final double? pct;
  final double? trendPct;

  double? get hours => minutes == null ? null : minutes! / 60;
  double? get days => minutes == null ? null : minutes! / 1440;

  bool get hasTrend => trendPct != null;

  /// "8.4%" — the sign is carried by the arrow and the colour.
  String get trendLabel {
    final pct = trendPct;
    if (pct == null) return '';
    final abs = pct.abs();
    return '${abs == abs.roundToDouble() ? abs.round() : abs.toStringAsFixed(1)}%';
  }

  bool get trendUp => (trendPct ?? 0) >= 0;

  static HelpKpi? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return HelpKpi(
      count: _int(raw['count']),
      minutes: _int(raw['minutes']),
      pct: _double(raw['pct']),
      trendPct: _double(raw['trend_pct']),
    );
  }

  @override
  List<Object?> get props => [count, minutes, pct, trendPct];
}

/// `GET /crm/dashboard-issue/kpis/` — the figures behind the Helpdesk home KPI
/// grid.
///
/// Every field is nullable: the route sits behind the dashboard permission and
/// answers 403 without it, so the screen has to work with none of this. What it
/// supplies that the ticket list cannot is the **trend** on each card and the
/// two medians — resolution and first response — which need per-ticket timing
/// the list does not carry.
class HelpKpis extends Equatable {
  const HelpKpis({
    this.openTickets,
    this.slaBreaches,
    this.avgResolution,
    this.firstResponse,
    this.reopenRate,
  });

  final HelpKpi? openTickets;
  final HelpKpi? slaBreaches;
  final HelpKpi? avgResolution;
  final HelpKpi? firstResponse;
  final HelpKpi? reopenRate;

  static HelpKpis? fromJson(Object? body) {
    if (body is! Map) return null;
    final kpis = HelpKpis(
      openTickets: HelpKpi.fromJson(body['open_tickets']),
      slaBreaches: HelpKpi.fromJson(body['sla_breaches']),
      avgResolution: HelpKpi.fromJson(body['avg_resolution']),
      firstResponse: HelpKpi.fromJson(body['first_response']),
      reopenRate: HelpKpi.fromJson(body['reopen_rate']),
    );
    // A 200 carrying none of the documented keys is not a usable payload.
    return kpis.props.any((p) => p != null) ? kpis : null;
  }

  @override
  List<Object?> get props =>
      [openTickets, slaBreaches, avgResolution, firstResponse, reopenRate];
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double? _double(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}
