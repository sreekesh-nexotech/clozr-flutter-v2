import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../core/config/api_config.dart';

/// A workspace member ("rep"). Shared across CRM, Operations, Helpdesk and LMS
/// because the prototype seeds one roster (`REPS`) used everywhere.
///
/// When the API lands, this becomes a domain entity hydrated from
/// `/users` — the presentation reads it exactly as-is.
class AppUser {
  final String id;
  final String name;
  final String initials;
  final Color color;
  final String role; // "Sales executive · Team Kochi"

  const AppUser({
    required this.id,
    required this.name,
    required this.initials,
    required this.color,
    required this.role,
  });

  String get firstName => name.split(' ').first;

  /// Team name parsed from the "role · team" convention.
  String get team {
    final parts = role.split('·');
    return parts.length > 1 ? parts[1].trim() : '';
  }
}

/// The prototype's `REPS` roster. Avatar colour is navy for all reps in the
/// CRM card context; the People module uses distinct per-member colours (see
/// [MockUsers.memberColors]).
class MockUsers {
  MockUsers._();

  static const List<AppUser> reps = [
    AppUser(id: 'me', name: 'Manoj Varma', initials: 'MV', color: AppColors.navy, role: 'System Admin · You'),
    AppUser(id: 'am', name: 'Anjana Menon', initials: 'AM', color: AppColors.navy, role: 'Sales executive · Team Kochi'),
    AppUser(id: 'rk', name: 'Rahul Krishnan', initials: 'RK', color: AppColors.navy, role: 'Sales executive · Team Kochi'),
    AppUser(id: 'fa', name: 'Fariz Ahmed', initials: 'FA', color: AppColors.navy, role: 'Sales executive · Team North Kerala'),
    AppUser(id: 'dr', name: 'Deepak Raj', initials: 'DR', color: AppColors.navy, role: 'Sales executive · Team South Kerala'),
    AppUser(id: 'st', name: 'Sneha Thomas', initials: 'ST', color: AppColors.navy, role: 'Sales executive · Team Kochi'),
    AppUser(id: 'an', name: 'Arjun Nair', initials: 'AN', color: AppColors.navy, role: 'Manager · Team Central'),
  ];

  static final Map<String, AppUser> byId = {for (final r in reps) r.id: r};

  /// Resolves a user id to a display user. In API mode an id that hasn't been
  /// registered (roster 403, or an embedded object with no name) must NOT fall
  /// back to the signed-in user — that silently misattributes ownership. It
  /// returns a neutral "Unknown" placeholder instead. In mock mode the roster
  /// is complete, so the first rep remains a harmless fallback.
  static AppUser of(String id) {
    final found = byId[id];
    if (found != null) return found;
    return ApiConfig.apiEnabled ? _unknown(id) : reps.first;
  }

  static AppUser _unknown(String id) => AppUser(
        id: id,
        name: 'Unknown',
        initials: id.isNotEmpty ? id.substring(0, 1).toUpperCase() : '?',
        color: AppColors.textPlaceholder,
        role: '',
      );

  /// Distinct per-member avatar colours used on the People screens (from the
  /// `members` seed).
  static const Map<String, Color> memberColors = {
    'mv': AppColors.navy,
    'lp': Color(0xFF35507C),
    'an': AppColors.teal,
    'am': AppColors.blueBright,
    'rk': AppColors.success,
    'fa': AppColors.pending,
    'dr': AppColors.warning,
    'st': AppColors.navyMid,
    'rj': AppColors.textPlaceholder,
  };
}
