import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../../../data/mock/mock_users.dart';
import '../../../domain/entities/reward.dart';
import '../../../presentation/rewards_tokens.dart';

/// Remote rewards data: HTTP via [ApiService] + JSON→[RewardsData] mapping.
/// No caching here — and none in the repository either (LMS/rewards
/// intentionally skip the Hive fallback; no dedicated cache box exists).
///
/// Mapping is a PARTIAL ENRICHMENT of the mock bundle: goals come from
/// `/milestones/progress/` rows (+ reward payloads from `/milestones/rewards/`
/// grants when readable); everything that is not derivable from those two
/// endpoints (profile.reportsTo, currentLevel, the Closer Track levels) keeps
/// the mock default by design.
class RewardsRemoteDataSource {
  RewardsRemoteDataSource(this._api);

  final ApiService _api;

  static const int _maxPages = 50; // safety cap; loop still breaks when next == null

  /// GET /milestones/progress/ rows (paginated, bounded), scoped to the
  /// signed-in user when the session id is known.
  Future<List<Map<String, dynamic>>> fetchProgressRows() => _pages(ApiEndpoints.milestoneProgress);

  /// GET /milestones/rewards/ grant rows. Visibility rules may 403 — the
  /// repository treats that as "no grants".
  Future<List<Map<String, dynamic>>> fetchGrantRows() => _pages(ApiEndpoints.milestoneRewards);

  Future<List<Map<String, dynamic>>> _pages(String path) async {
    final uid = UserDirectory.currentUserId;
    final rows = <Map<String, dynamic>>[];
    int? page;
    for (var i = 0; i < _maxPages; i++) {
      final body = await _api.get(path, query: {
        'page_size': ApiConfig.defaultPageSize,
        if (uid != null && uid.isNotEmpty) 'participant_user': uid,
        if (page != null) 'page': page,
      });
      final paged = Paginated.fromAny<Map<String, dynamic>>(body, (row) => row);
      rows.addAll(paged.results);
      page = _pageOf(paged.next);
      if (page == null) break;
    }
    return rows;
  }

  static int? _pageOf(String? next) {
    if (next == null || next.isEmpty) return null;
    final uri = Uri.tryParse(next);
    if (uri == null) return null;
    return int.tryParse(uri.queryParameters['page'] ?? '');
  }

  // ── Mapping (visible for tests) ──

  /// The mock seed's reward icon/bg/colour combos, cycled deterministically by
  /// goal index.
  static const List<(IconData, Color, Color)> visualCycle = [
    (PhosphorIconsFill.gift, AppColors.tintBlue, AppColors.blueBright),
    (PhosphorIconsFill.airplaneTilt, AppColors.tintGreen, AppColors.success),
    (PhosphorIconsFill.gasPump, AppColors.tintAmber, AppColors.warningDeep),
    (PhosphorIconsFill.trophy, RewardsColors.rewardPurpleBg, AppColors.pending),
  ];

  /// Builds the screen bundle from API rows on top of the mock [base].
  /// Malformed rows are skipped, never fatal. With zero progress rows the
  /// goals list is honestly empty (mock goals are NOT shown against a real
  /// backend); non-derivable fields always keep the [base] values.
  static RewardsData mapRewards({
    required RewardsData base,
    required List<dynamic> progressRows,
    List<dynamic> grantRows = const [],
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();

    // Grants indexed by "milestone|period" and by milestone alone (lifetime).
    final grantByKey = <String, Map<String, dynamic>>{};
    for (final g in grantRows) {
      if (g is! Map<String, dynamic>) continue;
      final milestone = g['milestone']?.toString() ?? '';
      if (milestone.isEmpty) continue;
      grantByKey['$milestone|${g['period_instance'] ?? ''}'] = g;
      grantByKey.putIfAbsent(milestone, () => g);
    }

    final current = <Map<String, dynamic>>[];
    final pastByMilestone = <String, List<Map<String, dynamic>>>{};
    final achievedMilestones = <String>{};
    DateTime? lastSwept;

    for (final row in progressRows) {
      if (row is! Map<String, dynamic>) continue;
      final milestone = row['milestone']?.toString() ?? '';
      final progressId = row['progress_id']?.toString() ?? '';
      if (milestone.isEmpty && progressId.isEmpty) continue;

      final swept = parseApiDate(row['last_swept_at']);
      if (swept != null && (lastSwept == null || swept.isAfter(lastSwept))) {
        lastSwept = swept;
      }
      if (row['achieved'] == true && milestone.isNotEmpty) {
        achievedMilestones.add(milestone);
      }

      final end = parseApiDate(row['period_end']);
      if (end != null && end.isBefore(ref)) {
        pastByMilestone.putIfAbsent(milestone, () => []).add(row);
      } else {
        current.add(row);
      }
    }

    final goals = <RewardGoal>[];
    for (final row in current) {
      final goal = mapGoal(
        row,
        index: goals.length,
        grantByKey: grantByKey,
        pastRows: pastByMilestone[row['milestone']?.toString() ?? ''] ?? const [],
      );
      if (goal != null) goals.add(goal);
    }

    // Profile: session identity (auth hydrates MockUsers['me']); milestone
    // count from achieved rows; reportsTo/currentLevel are not derivable from
    // these endpoints → mock defaults.
    final self = MockUsers.of('me');
    final selfRole = self.role.replaceAll(RegExp(r'\s*·\s*You$'), '').trim();
    final profile = RewardProfile(
      name: self.name,
      initials: self.initials,
      role: selfRole.isEmpty ? base.profile.role : selfRole,
      milestones: achievedMilestones.length,
      reportsTo: base.profile.reportsTo,
      currentLevel: base.profile.currentLevel,
    );

    return RewardsData(
      profile: profile,
      lastUpdated: lastSwept == null
          ? base.lastUpdated
          : DateFormat('d MMM yyyy, HH:mm').format(lastSwept.toLocal()),
      goals: goals,
      // Closer Track levels live on /milestones/tracks/ + /steps/ (not part
      // of this slice) → keep the mock structure untouched.
      closerTrack: base.closerTrack,
    );
  }

  /// Maps one open-period progress row onto a [RewardGoal]. Returns null when
  /// the row carries no usable id.
  static RewardGoal? mapGoal(
    Map<String, dynamic> row, {
    required int index,
    Map<String, Map<String, dynamic>> grantByKey = const {},
    List<Map<String, dynamic>> pastRows = const [],
  }) {
    final milestone = row['milestone']?.toString() ?? '';
    final id = row['progress_id']?.toString() ?? milestone;
    if (id.isEmpty) return null;

    final currentValue = parseAmount(row['current_value']);
    final target = parseAmount(row['target_snapshot']);
    final pct = progressPct(row, currentValue, target);
    final achieved = row['achieved'] == true;

    final grant = grantByKey['$milestone|${row['period_instance'] ?? ''}'] ??
        grantByKey[milestone];
    final grantStatus = grant?['status'] as String? ?? '';
    final snapshot = grant?['reward_snapshot'];
    final reward = snapshot is Map ? snapshot : const {};

    final pill = grantStatus == 'approved' || grantStatus == 'fulfilled'
        ? RewardPillKind.approved
        : (achieved || grantStatus == 'achieved')
            ? RewardPillKind.achieved
            : RewardPillKind.locked;

    final title = row['milestone_name'] as String? ?? 'Milestone';
    final visual = visualCycle[index % visualCycle.length];

    return RewardGoal(
      id: id,
      title: title,
      date: row['period_label'] as String? ?? '',
      pill: pill,
      achieveTitle: title,
      achieveSub: target > 0 ? 'Reach ${formatValue(target, target)} to unlock the reward' : '',
      progLeft: '${formatValue(currentValue, target)} / ${formatValue(target, target)}',
      progRight: '$pct%',
      progPct: pct,
      rwIcon: visual.$1,
      rwBg: visual.$2,
      rwColor: visual.$3,
      rwTitle: reward['title'] as String? ?? 'Reward',
      rwChip: reward['display_value'] as String? ?? '',
      rwDesc: reward['description'] as String? ?? '',
      pending: pill == RewardPillKind.achieved && grantStatus == 'achieved'
          ? 'Pending approval — you’ll be notified once it’s approved.'
          : '',
      past: [
        for (final p in pastRows)
          RewardPastRow(
            period: p['period_label'] as String? ?? '',
            result:
                '${formatValue(parseAmount(p['current_value']), parseAmount(p['target_snapshot']))} / ${formatValue(parseAmount(p['target_snapshot']), parseAmount(p['target_snapshot']))} · ${p['achieved'] == true ? 'Reward paid' : 'Missed'}',
            paid: p['achieved'] == true,
          ),
      ],
    );
  }

  /// Percent 0–100 from the row's `pct` (a 0–1 ratio server-side; values > 1
  /// are tolerated as pre-multiplied percents), falling back to
  /// current/target.
  static int progressPct(Map<String, dynamic> row, double current, double target) {
    final raw = parseAmount(row['pct']);
    double pct;
    if (raw > 0) {
      pct = raw <= 1 ? raw * 100 : raw;
    } else if (target > 0) {
      pct = current / target * 100;
    } else {
      pct = 0;
    }
    return pct.round().clamp(0, 100);
  }

  /// Progress numbers the way the mock shows them: plain integers for counts,
  /// `₹14,50,000`-style Indian grouping for money. The measure kind is not on
  /// the row, so a target ≥ 1000 is treated as a rupee amount (the fixed
  /// measure library only has counts and INR values).
  static String formatValue(double value, double target) {
    final money = target >= 1000;
    if (money) return '₹${NumberFormat.decimalPattern('en_IN').format(value.round())}';
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }
}
