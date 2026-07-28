import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../presentation/rewards_tokens.dart';
import '../../../domain/entities/reward.dart';

/// Static rewards seed — a 1:1 port of the prototype's `rwGoals` / `rwLevels`
/// and the profile markup (design lines 4907–5031, 10498–10525). This is the
/// ONLY place rewards sample data lives; swap it for a remote source and the
/// UI is unchanged.
class RewardsMockDataSource {
  const RewardsMockDataSource();

  RewardsData fetch() => RewardsData(
        profile: const RewardProfile(
          name: 'Manoj Varma',
          initials: 'MV',
          role: 'Business Owner',
          milestones: 5,
          reportsTo: 'Arjun Nair',
          currentLevel: 'Level 2 · ₹25L Booked',
        ),
        lastUpdated: '9 Jul 2026, 06:00',
        goals: [
          RewardGoal(
            id: 'g1',
            title: 'Monthly Deal Closer',
            date: '1–31 Jul 2026',
            pill: RewardPillKind.locked,
            achieveTitle: 'Deals won this month',
            achieveSub: 'Reach 5 to unlock the reward',
            progLeft: '3 / 5',
            progRight: '60%',
            progPct: 60,
            rwIcon: PhosphorIconsFill.gift,
            rwBg: AppColors.tintBlue,
            rwColor: AppColors.blueBright,
            rwTitle: '₹10,000 shopping voucher',
            rwChip: '₹10,000',
            rwDesc: 'A ₹10,000 gift voucher, settled with payroll at month end.',
            past: const [
              RewardPastRow(period: 'Jun 2026', result: '5 / 5 · Reward paid', paid: true),
              RewardPastRow(period: 'May 2026', result: '4 / 5 · Missed', paid: false),
              RewardPastRow(period: 'Apr 2026', result: '5 / 5 · Reward paid', paid: true),
            ],
          ),
          RewardGoal(
            id: 'g2',
            title: 'Quarterly ₹50L Club',
            date: 'Jul–Sep 2026',
            pill: RewardPillKind.achieved,
            achieveTitle: 'Won deal value this quarter (modular kitchen only)',
            achieveSub: 'Reach ₹50,00,000 to unlock the reward',
            progLeft: '₹52,00,000 / ₹50,00,000',
            progRight: '100%',
            progPct: 100,
            rwIcon: PhosphorIconsFill.airplaneTilt,
            rwBg: AppColors.tintGreen,
            rwColor: AppColors.success,
            rwTitle: 'Weekend for two — Munnar',
            rwChip: 'Getaway',
            rwDesc: 'A two-night stay for two at a Munnar resort.',
            pending: 'Pending approval — you’ll be notified once it’s approved.',
            past: const [
              RewardPastRow(period: 'Apr–Jun 2026', result: '₹41,00,000 / ₹50,00,000 · Missed', paid: false),
            ],
          ),
          RewardGoal(
            id: 'g3',
            title: 'Cash Collection Sprint',
            date: '1–31 Jul 2026',
            pill: RewardPillKind.locked,
            achieveTitle: 'Cash collected this month',
            achieveSub: 'Reach ₹20,00,000 to unlock the reward',
            progLeft: '₹14,50,000 / ₹20,00,000',
            progRight: '73%',
            progPct: 73,
            rwIcon: PhosphorIconsFill.gasPump,
            rwBg: AppColors.tintAmber,
            rwColor: AppColors.warningDeep,
            rwTitle: '₹5,000 fuel card',
            rwChip: '₹5,000',
            rwDesc: 'A ₹5,000 fuel card top-up.',
            past: const [
              RewardPastRow(period: 'Jun 2026', result: '₹22,40,000 / ₹20,00,000 · Reward paid', paid: true),
            ],
          ),
          RewardGoal(
            id: 'g4',
            title: 'First 10 Conversions',
            date: 'One-shot · lifetime',
            pill: RewardPillKind.approved,
            achieveTitle: 'Conversions (lifetime)',
            achieveSub: 'Reach 10 to unlock the reward',
            progLeft: '10 / 10',
            progRight: '100%',
            progPct: 100,
            rwIcon: PhosphorIconsFill.trophy,
            rwBg: RewardsColors.rewardPurpleBg,
            rwColor: AppColors.pending,
            rwTitle: 'Rising Star trophy',
            rwChip: 'Recognition',
            rwDesc: 'A Rising Star trophy and a spotlight in the monthly all-hands.',
          ),
        ],
        closerTrack: const CloserTrack(
          upNextTitle: 'Level 3 · 25 Deals Won',
          upNextSub: 'Needs 25 deals won to unlock',
          progLeft: '14 / 25',
          progRight: '56%',
          pct: 56,
          levels: [
            RewardLevel(
              title: 'Level 4 · ₹1Cr Club',
              sub: '₹1Cr won value · Locked',
              kind: RewardLevelKind.locked,
            ),
            RewardLevel(
              title: 'Level 3 · 25 Deals Won',
              sub: '25 deals won · In progress',
              kind: RewardLevelKind.current,
              here: true,
            ),
            RewardLevel(
              title: 'Level 2 · ₹25L Booked',
              sub: '₹25L won value · ',
              subTail: 'Achieved',
              kind: RewardLevelKind.done,
            ),
            RewardLevel(
              title: 'Level 1 · First 10 Conversions',
              sub: '10 conversions · ',
              subTail: 'Achieved',
              kind: RewardLevelKind.done,
              hasLine: false,
            ),
          ],
        ),
      );
}
