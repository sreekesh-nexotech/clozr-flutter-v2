import 'package:flutter/material.dart';

/// Messages-only colour tokens — the prototype hexes on the Messages/Chat
/// screens that are not in the shared [AppColors] palette. Named and centralised
/// so widgets never inline raw hex.
class MessagesColors {
  MessagesColors._();

  static const muted = Color(0xFF6C6C6C); // composer glyphs, closed-window text
  static const inputBorder = Color(0xFFE6E7EA); // search / composer field ring
  static const myBubbleBorder = Color(0xFFD9E8FF); // outgoing bubble ring
  static const todayChip = Color(0xFFECEDEF); // "Today" date separator chip
  static const sendDisabled = Color(0xFFC7CBD3); // send FAB when draft empty
  static const windowSub = Color(0xFF4A7C5B); // open-window sublabel green
  static const infoBannerBg = Color(0xFFF6F8FB); // template-picker info banner tint
}
