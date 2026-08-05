// De-mock guarantees for rewards (audit L-3 / M2): the neutral empty bundle and
// the fact that mapRewards leaks NO mock data when given an empty base — every
// non-derivable field stays honestly empty in API mode.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/rewards/domain/entities/reward.dart';
import 'package:clozrapp/features/rewards/infrastructure/data_sources/remote/rewards_remote_ds.dart';

final now = DateTime.parse('2026-07-09T09:41:00Z');

Map<String, dynamic> progressRow({
  Object? current = '3.00',
  Object? target = '5.00',
  Object? pct = '0.6000',
  bool achieved = false,
  Object? periodEnd = '2026-08-01T00:00:00Z',
  Object? lastSwept,
}) =>
    {
      'progress_id': 'p-1',
      'milestone': 'm-1',
      'milestone_name': 'Monthly Deal Closer',
      'period_instance': 11,
      'period_label': '1 Jul – 31 Jul 2026',
      'period_end': periodEnd,
      'current_value': current,
      'target_snapshot': target,
      'pct': pct,
      'achieved': achieved,
      if (lastSwept != null) 'last_swept_at': lastSwept,
    };

void main() {
  group('RewardsData.empty', () {
    test('is a neutral, mock-free bundle', () {
      final e = RewardsData.empty();
      expect(e.profile.name, isEmpty);
      expect(e.profile.initials, isEmpty);
      expect(e.profile.role, isEmpty);
      expect(e.profile.reportsTo, isEmpty);
      expect(e.profile.currentLevel, isEmpty);
      expect(e.profile.milestones, 0);
      expect(e.lastUpdated, isEmpty);
      expect(e.goals, isEmpty);
      expect(e.closerTrack.levels, isEmpty);
      expect(e.closerTrack.isEmpty, isTrue);
    });
  });

  group('mapRewards no longer leaks mock when the base is empty', () {
    test('non-derivable fields stay empty; goals still come from the rows', () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: RewardsData.empty(),
        progressRows: [progressRow(achieved: true, lastSwept: '2026-07-08T02:15:00Z')],
        now: now,
      );
      // Not derivable from the milestone endpoints → must stay empty (no mock).
      expect(data.profile.reportsTo, isEmpty);
      expect(data.profile.currentLevel, isEmpty);
      expect(data.closerTrack.isEmpty, isTrue);
      expect(data.closerTrack.levels, isEmpty);
      // Derivable → present.
      expect(data.goals, hasLength(1));
      expect(data.profile.milestones, 1); // achieved count
      expect(data.lastUpdated, isNotEmpty); // from last_swept_at
    });

    test('zero rows against an empty base is completely empty (no mock seed)', () {
      final data = RewardsRemoteDataSource.mapRewards(
        base: RewardsData.empty(),
        progressRows: const [],
        now: now,
      );
      expect(data.goals, isEmpty);
      expect(data.profile.milestones, 0);
      expect(data.profile.reportsTo, isEmpty);
      expect(data.profile.currentLevel, isEmpty);
      expect(data.lastUpdated, isEmpty); // empty base, nothing swept
      expect(data.closerTrack.isEmpty, isTrue);
    });
  });
}
