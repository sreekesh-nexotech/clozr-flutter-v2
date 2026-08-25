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

  /// The manager's `user_id`. Kept beside [reportsTo] because that is only a
  /// display name: `members.md` identifies a manager by uuid (`manager_id`),
  /// and two people can share a full name.
  final String managerId;
  final String team; // team name or "—"
  final String status; // active | invited | inactive

  // ── Retrieve-only fields (`GET /management/users/{id}/`, members.md §4.1) ──
  //
  // The paginated list does not carry these — `scope` above all, which runs a
  // per-user permission lookup — so they stay at their defaults on a member
  // read out of the list, and fill in once the detail call lands.

  /// `profile.designation` ("Business Owner"). Distinct from [role]: one is the
  /// job title, the other the permission set.
  final String designation;

  /// `profile.timezone`, raw IANA ("Asia/Kolkata"). The "(IST)" suffix is
  /// rendered client-side.
  final String timezone;

  /// `territories[]` — the territories this user **manages**. There is no
  /// per-user territory assignment; territory is a Lead attribute.
  final List<String> territories;

  /// `is_protected` — a superuser/staff account the API blocks edits on.
  final bool isProtected;

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
    this.managerId = '',
    required this.team,
    required this.status,
    this.designation = '',
    this.timezone = '',
    this.territories = const [],
    this.isProtected = false,
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

/// One row of a member's activity feed
/// (`GET /management/users/{user_id}/activity/`, `members.md` §4.3).
///
/// The server humanises these — [label] arrives ready to render — so unlike the
/// CRM audit log there is no diff to interpret client-side.
class MemberActivity extends Equatable {
  const MemberActivity({
    required this.type,
    required this.label,
    this.actor = '',
    this.at,
  });

  /// `joined` | `login` | `role_assign` | an audit action. Drives the icon.
  final String type;

  /// The already-readable headline ("Signed in", "Role updated").
  final String label;

  /// Who did it, by display name. Empty for a system-generated entry.
  final String actor;

  /// When it happened; null when the row carried no parsable timestamp.
  final DateTime? at;

  @override
  List<Object?> get props => [type, label, actor, at];
}
