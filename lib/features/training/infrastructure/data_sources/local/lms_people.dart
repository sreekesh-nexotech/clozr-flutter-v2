import 'package:flutter/widgets.dart';
import '../../../../../app/theme/app_colors.dart';

/// A learner's identity for the LMS surfaces — name, initials and avatar
/// colour. Mirrors the prototype's `lmsNames` map (distinct per-member colours,
/// includes members not in the CRM roster such as Reena Jacob).
class LmsPerson {
  final String name;
  final String initials;
  final Color color;
  final String role;
  const LmsPerson(this.name, this.initials, this.color, this.role);

  String get firstName => name.split(' ').first;
}

/// LMS people directory. Seeded with the design's `lmsNames` roster (colours
/// map 1:1 to the design hexes via [AppColors]; roles come from `LMS_ROLE`).
/// The map is mutable by design: in API mode the remote data source
/// [register]s real org learners so `LmsPeople.of(uuid)` resolves their
/// name/initials instead of the '?' placeholder.
class LmsPeople {
  LmsPeople._();

  static final Map<String, LmsPerson> byId = {
    'me': const LmsPerson('Manoj Varma', 'MV', AppColors.navy, 'System Admin'),
    'an': const LmsPerson('Arjun Nair', 'AN', AppColors.teal, 'Manager'),
    'am': const LmsPerson('Anjana Menon', 'AM', AppColors.blueBright, 'Sales rep'),
    'rk': const LmsPerson('Rahul Krishnan', 'RK', AppColors.success, 'Sales rep'),
    'fa': const LmsPerson('Fariz Ahmed', 'FA', AppColors.pending, 'Sales rep'),
    'dr': const LmsPerson('Deepak Raj', 'DR', AppColors.warning, 'Sales rep'),
    'st': const LmsPerson('Sneha Thomas', 'ST', AppColors.navyMid, 'Project associate'),
    'rj': const LmsPerson('Reena Jacob', 'RJ', AppColors.textPlaceholder, 'Viewer'),
  };

  static const List<Color> _palette = [
    AppColors.navy,
    AppColors.teal,
    AppColors.blueBright,
    AppColors.success,
    AppColors.pending,
    AppColors.warning,
    AppColors.navyMid,
  ];
  static int _colorSeq = 0;

  /// Adds/refreshes a real learner (API mode). Initials are derived from the
  /// name; avatar colours cycle the design palette deterministically.
  static void register({required String rid, required String name, String role = ''}) {
    if (rid.isEmpty || name.isEmpty) return;
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? (parts.first[0] + parts.last[0]).toUpperCase()
        : (parts.first.length >= 2 ? parts.first.substring(0, 2) : parts.first).toUpperCase();
    byId[rid] = LmsPerson(
      name,
      initials,
      byId[rid]?.color ?? _palette[_colorSeq++ % _palette.length],
      role.isEmpty ? 'Viewer' : role,
    );
  }

  static LmsPerson of(String rid) =>
      byId[rid] ?? const LmsPerson('?', '?', AppColors.textMuted, 'Viewer');
}
