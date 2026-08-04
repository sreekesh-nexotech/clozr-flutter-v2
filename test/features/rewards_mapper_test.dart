// Fixture → entity assertions for the rewards (milestones) remote mappers.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/app/theme/app_colors.dart';
import 'package:clozrapp/features/rewards/domain/entities/reward.dart';
import 'package:clozrapp/features/rewards/infrastructure/data_sources/local/rewards_mock_ds.dart';
import 'package:clozrapp/features/rewards/infrastructure/data_sources/remote/rewards_remote_ds.dart';
import 'package:clozrapp/features/rewards/infrastructure/repositories/rewards_repository_impl.dart';

/// Pinned "now" so open vs past period classification is deterministic.
final now = DateTime.parse('2026-07-09T09:41:00Z');

final base = const RewardsMockDataSource().fetch();

Map<String, dynamic> progressRow({
  String id = 'p-1',
  String milestone = 'm-1',
  String name = 'Monthly Deal Closer',
  Object? current = '3.00',
  Object? target = '5.00',
  Object? pct = '0.6000',
  bool achieved = false,
  Object? periodEnd = '2026-08-01T00:00:00Z',
  Object? periodInstance = 11,
  // Distinct from the mock's "9 Jul 2026, 06:00" so derived-vs-default
  // lastUpdated assertions can tell them apart.
  String lastSwept = '2026-07-08T02:15:00Z',
}) =>
    {
      'progress_id': id,
      'milestone': milestone,
      'milestone_name': name,
      'period_instance': periodInstance,
      'period_label': '1 Jul – 31 Jul 2026',
      'period_end': periodEnd,
      'current_value': current,
      'target_snapshot': target,
      'pct': pct,
      'achieved': achieved,
      'last_swept_at': lastSwept,
    };

void main() {
  group('mapRewards — goals from progress rows', () {
    test('count milestone: "3 / 5", 60%, locked pill', () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: base,
        progressRows: [progressRow()],
        now: now,
      );
      expect(data.goals, hasLength(1));
      final g = data.goals.first;
      expect(g.id, 'p-1');
      expect(g.title, 'Monthly Deal Closer');
      expect(g.date, '1 Jul – 31 Jul 2026');
      expect(g.progLeft, '3 / 5');
      expect(g.progRight, '60%');
      expect(g.progPct, 60);
      expect(g.pill, RewardPillKind.locked);
      expect(g.achieveSub, 'Reach 5 to unlock the reward');
      expect(g.pending, isEmpty);
    });

    test('money milestone: Indian-grouped rupees and rounded pct', () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: base,
        progressRows: [
          progressRow(
              current: '1450000.00', target: '2000000.00', pct: '0.7250'),
        ],
        now: now,
      );
      final g = data.goals.first;
      expect(g.progLeft, '₹14,50,000 / ₹20,00,000');
      expect(g.progRight, '73%');
      expect(g.progPct, 73);
      expect(g.achieveSub, 'Reach ₹20,00,000 to unlock the reward');
    });

    test('grant enrichment: approved pill + reward copy from the snapshot',
        () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: base,
        progressRows: [progressRow(achieved: true, pct: '1.0000')],
        grantRows: [
          {
            'milestone': 'm-1',
            'period_instance': 11,
            'status': 'approved',
            'reward_snapshot': {
              'title': '₹10,000 shopping voucher',
              'display_value': '₹10,000',
              'description': 'Settled with payroll.',
            },
          }
        ],
        now: now,
      );
      final g = data.goals.first;
      expect(g.pill, RewardPillKind.approved);
      expect(g.progPct, 100);
      expect(g.rwTitle, '₹10,000 shopping voucher');
      expect(g.rwChip, '₹10,000');
      expect(g.rwDesc, 'Settled with payroll.');
    });

    test('achieved-but-unapproved grant shows the pending approval note', () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: base,
        progressRows: [progressRow(achieved: true)],
        grantRows: [
          {'milestone': 'm-1', 'period_instance': 11, 'status': 'achieved'},
        ],
        now: now,
      );
      final g = data.goals.first;
      expect(g.pill, RewardPillKind.achieved);
      expect(g.pending, isNotEmpty);
      expect(g.rwTitle, 'Reward'); // no snapshot → generic copy
    });

    test('closed periods land as past rows on the open goal', () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: base,
        progressRows: [
          progressRow(),
          progressRow(
            id: 'p-0',
            current: '5.00',
            achieved: true,
            periodEnd: '2026-07-01T00:00:00Z',
            periodInstance: 10,
          ),
          progressRow(
            id: 'p-x',
            current: '4.00',
            achieved: false,
            periodEnd: '2026-06-01T00:00:00Z',
            periodInstance: 9,
          ),
        ],
        now: now,
      );
      expect(data.goals, hasLength(1));
      final past = data.goals.first.past;
      expect(past, hasLength(2));
      expect(past[0].result, '5 / 5 · Reward paid');
      expect(past[0].paid, isTrue);
      expect(past[1].result, '4 / 5 · Missed');
      expect(past[1].paid, isFalse);
    });

    test('reward visuals cycle deterministically and wrap at 4', () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: base,
        progressRows: [
          for (var i = 0; i < 5; i++)
            progressRow(id: 'p-$i', milestone: 'm-$i'),
        ],
        now: now,
      );
      expect(data.goals, hasLength(5));
      expect(data.goals[0].rwBg, AppColors.tintBlue);
      expect(data.goals[1].rwColor, AppColors.success);
      expect(data.goals[4].rwIcon, data.goals[0].rwIcon); // wrap
    });
  });

  group('mapRewards — partial enrichment keeps mock defaults', () {
    test('non-derivable profile fields and the Closer Track stay mock', () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: base,
        progressRows: [progressRow(achieved: true)],
        now: now,
      );
      expect(data.profile.reportsTo, base.profile.reportsTo);
      expect(data.profile.currentLevel, base.profile.currentLevel);
      expect(data.closerTrack, same(base.closerTrack));
      expect(data.profile.milestones, 1); // achieved count IS derivable
      expect(data.profile.name, isNotEmpty); // session identity
      expect(data.lastUpdated, isNot(base.lastUpdated)); // from last_swept_at
    });

    test('zero rows: goals honestly empty, the rest keeps mock defaults', () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: base,
        progressRows: const [],
        now: now,
      );
      expect(data.goals, isEmpty);
      expect(data.profile.milestones, 0);
      expect(data.lastUpdated, base.lastUpdated);
      expect(data.closerTrack, same(base.closerTrack));
    });
  });

  group('mapRewards — defensive nulls', () {
    test('malformed rows are skipped, never fatal', () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: base,
        progressRows: [42, 'nope', null, <String, dynamic>{}, progressRow()],
        grantRows: [7, <String, dynamic>{}],
        now: now,
      );
      expect(data.goals, hasLength(1));
    });

    test('missing pct falls back to current/target', () {
      final g = RewardsRemoteDataSource.mapGoal(
        progressRow(current: 2, target: 4, pct: null),
        index: 0,
      )!;
      expect(g.progPct, 50);
      expect(g.progLeft, '2 / 4');
    });

    test('zero target never divides by zero', () {
      final g = RewardsRemoteDataSource.mapGoal(
        progressRow(current: 0, target: 0, pct: null),
        index: 0,
      )!;
      expect(g.progPct, 0);
      expect(g.achieveSub, isEmpty);
    });
  });

  group('mock repository (async contract)', () {
    test('still serves the full mock bundle', () async {
      const repo = RewardsRepositoryImpl(RewardsMockDataSource());
      final data = await repo.getRewards();
      expect(data.goals, hasLength(4));
      expect(data.profile.name, 'Manoj Varma');
    });
  });
}
