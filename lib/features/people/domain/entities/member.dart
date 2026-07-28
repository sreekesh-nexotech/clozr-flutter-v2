import 'package:equatable/equatable.dart';

/// A workspace member (People module). Fields mirror the prototype's `members`
/// seed so the mock data source maps directly, and the shape is API-ready:
/// when `/members` lands, deserialize JSON into this exact entity and the UI is
/// unchanged.
class Member extends Equatable {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role; // key into role tone map, e.g. "Sales executive"
  final String scope; // visibility scope, e.g. "Self + Reporting Hierarchy"
  final String reportsTo; // manager name or "— (exempt)"
  final String team; // team name or "—"
  final String status; // active | invited | inactive

  // Performance snapshot (owned leads, all-time) — shown on the detail screen.
  final int perfOpen;
  final int perfClosed;
  final int perfWon;
  final String perfWonVal; // display, e.g. "₹1.47Cr"
  final String perfConv; // display, e.g. "100%" or "—"

  const Member({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.scope,
    required this.reportsTo,
    required this.team,
    required this.status,
    this.perfOpen = 0,
    this.perfClosed = 0,
    this.perfWon = 0,
    this.perfWonVal = '₹0L',
    this.perfConv = '—',
  });

  /// Two-letter initials from the display name.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  bool get isAdmin => role.toLowerCase().contains('admin');
  bool get hasTeam => team.isNotEmpty && team != '—';
  bool get hasManager => reportsTo.isNotEmpty && reportsTo != '—' && !reportsTo.startsWith('—');

  @override
  List<Object?> get props => [id];
}
