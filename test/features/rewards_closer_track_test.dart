// The Closer Track card was hidden in API mode on the assumption that its
// level data "is not derivable from the milestone endpoints". It is:
// `/milestones/tracks/` + `/milestones/steps/` + `/milestones/milestones/`
// describe the ladder, and `/milestones/progress/` says which rungs the
// signed-in user has cleared and how far along the next one they are.
//
// These run the **real** responses captured from Acme Corp (2026-09-12)
// through the mapper. Admin Acme has achieved Level 1 and is at 0 / 10,000 on
// Level 2, so the expected timeline is: Level 2 = current / YOU ARE HERE,
// Level 1 = done / Achieved.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/rewards/domain/entities/reward.dart';
import 'package:clozrapp/features/rewards/infrastructure/data_sources/remote/rewards_remote_ds.dart';

const _me = 'afaebf55-8bfc-4600-8fa9-c9071f077de0';

List<dynamic> _rows(String name) {
  final body = jsonDecode(File('test/fixtures/rewards/$name.json').readAsStringSync());
  return (body as Map<String, dynamic>)['results'] as List<dynamic>;
}

/// The live `/milestones/progress/` call is scoped to the signed-in user;
/// the fixture was captured unscoped, so narrow it the same way here.
List<dynamic> _myProgress() =>
    _rows('progress').where((r) => r['participant_user'] == _me).toList();

CloserTrack _track({List<dynamic>? progress}) => RewardsRemoteDataSource.mapCloserTrack(
      trackRows: _rows('tracks'),
      stepRows: _rows('steps'),
      milestoneRows: _rows('milestones'),
      progressRows: progress ?? _myProgress(),
      fallback: RewardsData.empty().closerTrack,
    );

void main() {
  test('the org track becomes a two-level timeline', () {
    final t = _track();
    expect(t.isEmpty, isFalse);
    expect(t.levels.map((l) => l.title), ['Level 2', 'Level 1']);
  });

  test('achieved is a tick, the next step is YOU ARE HERE', () {
    final t = _track();
    final level2 = t.levels[0];
    final level1 = t.levels[1];

    expect(level2.kind, RewardLevelKind.current);
    expect(level2.here, isTrue);

    expect(level1.kind, RewardLevelKind.done);
    expect(level1.subTail, 'Achieved');
    expect(level1.here, isFalse);
  });

  test('the connector runs down to the lowest level only', () {
    final t = _track();
    expect(t.levels.first.hasLine, isTrue);
    expect(t.levels.last.hasLine, isFalse);
  });

  test('up next reads the real progress row, not a level count', () {
    final t = _track();
    expect(t.upNextTitle, 'Level 2');
    expect(t.upNextSub, 'Needs ₹10K cash collected to unlock');
    expect(t.levels[1].sub, '2 conversions · ');
    // 0.00 current of a 10000.00 target on Level 2.
    expect(t.progLeft, '0 / ₹10K');
    expect(t.progRight, '0%');
    expect(t.pct, 0);
  });

  test('a later step is locked when the one before it is not done', () {
    // Nothing achieved: Level 1 is current, Level 2 locked.
    final t = _track(progress: const []);
    expect(t.levels.map((l) => l.kind),
        [RewardLevelKind.locked, RewardLevelKind.current]);
    expect(t.levels[1].here, isTrue);
  });

  test('every level cleared still leaves a marker and says so', () {
    final all = [
      for (final r in _myProgress())
        {...r as Map<String, dynamic>, 'achieved': true},
    ];
    final t = _track(progress: all);
    expect(t.levels.every((l) => l.kind == RewardLevelKind.done), isTrue);
    expect(t.levels.first.here, isTrue);
    expect(t.upNextTitle, 'All levels achieved');
  });

  test('no track, or a track with no steps, hides the card', () {
    final none = RewardsRemoteDataSource.mapCloserTrack(
      trackRows: const [],
      stepRows: _rows('steps'),
      milestoneRows: _rows('milestones'),
      progressRows: _myProgress(),
      fallback: RewardsData.empty().closerTrack,
    );
    expect(none.isEmpty, isTrue);

    final noSteps = RewardsRemoteDataSource.mapCloserTrack(
      trackRows: _rows('tracks'),
      stepRows: const [],
      milestoneRows: _rows('milestones'),
      progressRows: _myProgress(),
      fallback: RewardsData.empty().closerTrack,
    );
    expect(noSteps.isEmpty, isTrue);
  });

  test('the profile current level is the highest achieved on the track', () {
    final data = RewardsRemoteDataSource.mapRewards(
      base: RewardsData.empty(),
      progressRows: _myProgress(),
      trackRows: _rows('tracks'),
      stepRows: _rows('steps'),
      milestoneRows: _rows('milestones'),
    );
    expect(data.profile.currentLevel, 'Level 1');
    // No endpoint reports a manager; the header hides the line.
    expect(data.profile.reportsTo, '');
  });

  test('with nothing achieved the current level stays empty, not invented', () {
    final data = RewardsRemoteDataSource.mapRewards(
      base: RewardsData.empty(),
      progressRows: const [],
      trackRows: _rows('tracks'),
      stepRows: _rows('steps'),
      milestoneRows: _rows('milestones'),
    );
    expect(data.profile.currentLevel, '');
  });
}
