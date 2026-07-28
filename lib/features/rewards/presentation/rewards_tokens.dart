import 'package:flutter/material.dart';

/// Rewards-only colour tokens — the handful of prototype hexes on the My Rewards
/// screen that are not in the shared [AppColors] palette. Kept named and in one
/// place so widgets never inline raw hex.
class RewardsColors {
  RewardsColors._();

  static const refreshText = Color(0xFF35507E); // refresh-note copy
  static const muted = Color(0xFF6C6C6C); // progRight / past chevron / labels
  static const rewardPurpleBg = Color(0xFFF3E8FA); // trophy reward chip bg
  static const achievedBorder = Color(0xFFCBE8D4); // "Achieved" pill inset ring
  static const trackBg = Color(0xFFE8EAEE); // progress track + level connector
  static const chipBorder = Color(0xFFE6E7EA); // reward value chip inset ring
  static const pastRowBg = Color(0xFFFAFBFC); // expanded past-period rows
}
