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

/// Static LMS people directory. Colours map 1:1 to the design's `lmsNames`
/// hexes via [AppColors]; roles come from `LMS_ROLE`.
class LmsPeople {
  LmsPeople._();

  static const Map<String, LmsPerson> byId = {
    'me': LmsPerson('Manoj Varma', 'MV', AppColors.navy, 'System Admin'),
    'an': LmsPerson('Arjun Nair', 'AN', AppColors.teal, 'Manager'),
    'am': LmsPerson('Anjana Menon', 'AM', AppColors.blueBright, 'Sales rep'),
    'rk': LmsPerson('Rahul Krishnan', 'RK', AppColors.success, 'Sales rep'),
    'fa': LmsPerson('Fariz Ahmed', 'FA', AppColors.pending, 'Sales rep'),
    'dr': LmsPerson('Deepak Raj', 'DR', AppColors.warning, 'Sales rep'),
    'st': LmsPerson('Sneha Thomas', 'ST', AppColors.navyMid, 'Project associate'),
    'rj': LmsPerson('Reena Jacob', 'RJ', AppColors.textPlaceholder, 'Viewer'),
  };

  static LmsPerson of(String rid) =>
      byId[rid] ?? const LmsPerson('?', '?', AppColors.textMuted, 'Viewer');
}
