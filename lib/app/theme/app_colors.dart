import 'package:flutter/material.dart';

/// Clozr brand palette — sourced 1:1 from the design system
/// (`_ds/tokens/colors.css`) and the prototype's inline status maps.
///
/// Keep these as the single source of truth for every colour used in the
/// presentation layer. Do not hardcode hex values in widgets.
class AppColors {
  AppColors._();

  // ── Brand / Primary ──
  static const navy = Color(0xFF00113B); // Primary navy — navbar, CTAs, active
  static const navyMid = Color(0xFF152856); // Hover / secondary navy
  static const blueBright = Color(0xFF074ADB); // Links, "New" status, active tab
  static const blueSubtle = Color(0xFFEEF6FF); // Active tab bg
  static const blueTint = Color(0xFFEFF7FF); // CTA button bg
  static const blueCta = Color(0xFFEFF4FB); // Lead card call button bg

  // ── Status / Semantic ──
  static const success = Color(0xFF0E8F3D); // Green — Active/won
  static const warning = Color(0xFFEDA032); // Amber — Attempted/pending
  static const warningDeep = Color(0xFFE2890D); // Deeper amber (delta chips)
  static const error = Color(0xFFE71111); // Red — errors, breaches, badges
  static const errorDeep = Color(0xFFB42318); // Expired
  static const pending = Color(0xFF890DB6); // Purple — pending/review

  // ── Graph / Accent ──
  static const lime = Color(0xFFBEDD34);
  static const teal = Color(0xFF2C687B);
  static const tealLight = Color(0xFF8CC7C4);

  // ── Neutrals ──
  static const black = Color(0xFF000000);
  static const nearBlack = Color(0xFF0D0D0D);
  static const ink = Color(0xFF0B0B0F); // Logo / darkest headings
  static const textPrimary = Color(0xFF14151A); // Headings in prototype
  static const textPrimaryAlt = Color(0xFF1A1A1A);
  static const textBody = Color(0xFF202124);
  static const textDark = Color(0xFF282828);
  static const textSecondary = Color(0xFF363636);
  static const textLabel = Color(0xFF515151);
  static const textLabelAlt = Color(0xFF535151);
  static const textCaption = Color(0xFF717171);
  static const textMuted = Color(0xFF848383);
  static const textMuted2 = Color(0xFF6B6B6B);
  static const textPlaceholder = Color(0xFF9AA0A6);
  static const textBodyMuted = Color(0xFF4A4A4A);

  // ── Backgrounds ──
  static const bgApp = Color(0xFFFDFDFD);
  static const bgScreen = Color(0xFFF6F7F9); // list screen bg
  static const bgDetail = Color(0xFFF4F5F7); // detail screen bg
  static const bgPage = Color(0xFFF9FAFB);
  static const bgLight = Color(0xFFF3F4F5);
  static const bgSubtle = Color(0xFFEBF0F4);
  static const bgInput = Color(0xFFEFEFEF);
  static const bgHover = Color(0xFFF1F3F4);
  static const bgChipGrey = Color(0xFFF1F2F4);
  static const white = Color(0xFFFFFFFF);

  // ── Borders & strokes ──
  static const borderCard = Color(0xFFE8E9EB);
  static const borderCardSoft = Color(0xFFEEF0F3); // header divider / card inset
  static const borderInput = Color(0xFFDADADA);
  static const borderLight = Color(0xFFEEEEEE);
  static const borderMedium = Color(0xFFDFDCDC);
  static const borderGrey = Color(0xFFE0E0E0);
  static const borderChip = Color(0xFFEAEBEE);

  // ── Status-tint backgrounds (pills / stat chips) ──
  static const tintGreen = Color(0xFFE7F6EC);
  static const tintBlue = Color(0xFFEEF6FF);
  static const tintAmber = Color(0xFFFFF5EB);
  static const tintRed = Color(0xFFFCEBEB);
  static const tintPurple = Color(0xFFF3EAFF);
  static const tintNavy = Color(0xFFEAECF3);
  static const tintRedSoft = Color(0xFFFFE9E9);
  static const tintGrey = Color(0xFFF1F2F4);

  // ── Toast ──
  static const toastCheck = Color(0xFF4ADE80);

  /// Scrim used behind sheets / drawer.
  static const scrim = Color(0x6B0A0C16); // rgba(10,12,22,0.42)
}
