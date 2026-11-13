import '../domain/entities/help_dashboard.dart';
import '../domain/entities/help_kpis.dart';

/// The SLA donut's three figures.
typedef SlaCounts = ({int within, int atRisk, int breached});

/// The priority donut's four figures.
typedef PriorityCounts = ({int critical, int high, int medium, int low});

/// Rules behind Helpdesk Home that decide which source a figure comes from.
/// Kept pure so each one has a unit test.
abstract final class HelpHomeRules {
  /// The server KPI whose trend chip may sit beside a card showing [shown].
  ///
  /// The cards count the user's own tickets (the Support Overview with
  /// `assigned_to_me`), while `dashboard-issue/kpis?scope=own` can measure a
  /// wider set — an admin's "own" scope returned 4 open tickets for a user with
  /// none assigned. A chip belongs to the figure the server measured, so it is
  /// shown only when the server's count equals the displayed one, never
  /// "0 ↑12%" beside a figure that came from somewhere else.
  static HelpKpi? trendFor(HelpKpi? kpi, int shown) =>
      kpi != null && kpi.count == shown && kpi.hasTrend ? kpi : null;

  /// Whether the server's SLA / priority mix says anything. It is measured over
  /// tickets created in the selected period, so a user whose open tickets are
  /// older answers all zeros — which would draw an empty donut beside a card
  /// that reports a breach.
  static bool mixIsEmpty(SlaPriorityMix? mix) =>
      mix == null ||
      mix.withinSla + mix.atRisk + mix.breached == 0 &&
          mix.low + mix.medium + mix.high + mix.critical == 0;

  /// SLA donut: the server's mix when it counted anything, otherwise the same
  /// figures the cards use ([local]).
  static SlaCounts sla(SlaPriorityMix? mix, SlaCounts local) => mixIsEmpty(mix)
      ? local
      : (
          within: mix!.withinSla,
          atRisk: mix.atRisk,
          breached: mix.breached,
        );

  /// Priority donut, with the same fallback as [sla].
  static PriorityCounts priority(SlaPriorityMix? mix, PriorityCounts local) =>
      mixIsEmpty(mix)
          ? local
          : (
              critical: mix!.critical,
              high: mix.high,
              medium: mix.medium,
              low: mix.low,
            );
}
