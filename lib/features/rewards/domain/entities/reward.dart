import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

/// Visual state of a goal's reward pill (the prototype's `rwPills`).
enum RewardPillKind { locked, achieved, approved }

/// Where a level sits on the Closer Track (`rwLevels[].kind`).
enum RewardLevelKind { locked, current, done }

/// The rep's rewards profile header (name, tier, milestones).
class RewardProfile extends Equatable {
  const RewardProfile({
    required this.name,
    required this.initials,
    required this.role,
    required this.milestones,
    required this.reportsTo,
    required this.currentLevel,
  });

  final String name;
  final String initials;
  final String role;
  final int milestones;
  final String reportsTo;
  final String currentLevel; // "Level 2 · ₹25L Booked"

  @override
  List<Object?> get props => [name, initials, role, milestones, reportsTo, currentLevel];
}

/// One past-period result row inside a goal card.
class RewardPastRow extends Equatable {
  const RewardPastRow({required this.period, required this.result, required this.paid});

  final String period;
  final String result;
  final bool paid; // true → reward paid (green), false → missed (muted)

  @override
  List<Object?> get props => [period, result, paid];
}

/// A single rewards goal card (`rwGoals[]`).
class RewardGoal extends Equatable {
  const RewardGoal({
    required this.id,
    required this.title,
    required this.date,
    required this.pill,
    required this.achieveTitle,
    required this.achieveSub,
    required this.progLeft,
    required this.progRight,
    required this.progPct,
    required this.rwIcon,
    required this.rwBg,
    required this.rwColor,
    required this.rwTitle,
    required this.rwChip,
    required this.rwDesc,
    this.pending = '',
    this.past = const [],
  });

  final String id;
  final String title;
  final String date;
  final RewardPillKind pill;
  final String achieveTitle;
  final String achieveSub;
  final String progLeft;
  final String progRight;
  final int progPct;
  final IconData rwIcon;
  final Color rwBg;
  final Color rwColor;
  final String rwTitle;
  final String rwChip;
  final String rwDesc;
  final String pending; // '' when none
  final List<RewardPastRow> past;

  bool get hasPending => pending.isNotEmpty;
  bool get hasPast => past.isNotEmpty;

  @override
  List<Object?> get props => [id];
}

/// A level marker on the Closer Track timeline (`rwLevels[]`).
class RewardLevel extends Equatable {
  const RewardLevel({
    required this.title,
    required this.sub,
    required this.kind,
    this.subTail = '',
    this.here = false,
    this.hasLine = true,
  });

  final String title;
  final String sub;
  final RewardLevelKind kind;
  final String subTail; // "Achieved" tail, '' when none
  final bool here; // "YOU ARE HERE" badge
  final bool hasLine; // connector below the dot

  bool get hasTail => subTail.isNotEmpty;

  @override
  List<Object?> get props => [title, sub, kind, subTail, here, hasLine];
}

/// The Closer Track card: an "up next" progress block + the level timeline.
class CloserTrack extends Equatable {
  const CloserTrack({
    required this.upNextTitle,
    required this.upNextSub,
    required this.progLeft,
    required this.progRight,
    required this.pct,
    required this.levels,
  });

  final String upNextTitle;
  final String upNextSub;
  final String progLeft;
  final String progRight;
  final int pct;
  final List<RewardLevel> levels;

  @override
  List<Object?> get props => [upNextTitle, progLeft, pct, levels];
}

/// Everything the My Rewards screen renders, in one immutable bundle.
class RewardsData extends Equatable {
  const RewardsData({
    required this.profile,
    required this.lastUpdated,
    required this.goals,
    required this.closerTrack,
  });

  final RewardProfile profile;
  final String lastUpdated;
  final List<RewardGoal> goals;
  final CloserTrack closerTrack;

  @override
  List<Object?> get props => [profile, lastUpdated, goals, closerTrack];
}
