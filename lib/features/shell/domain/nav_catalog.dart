import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/router/routes.dart';
import '../../auth/domain/entities/module_access.dart';

/// A leaf row inside a grouped [NavEntry] (e.g. "Customers" under "CRM").
class NavGroupChild {
  final String label;
  final String path;

  /// Backend module keys (`docs-flutter/permissions.md`) that make this row
  /// visible. Empty = never gated.
  final List<String> modules;
  const NavGroupChild(this.label, this.path, {this.modules = const []});
}

/// One top-level drawer/landing destination.
class NavEntry {
  final String key;
  final String label;
  final IconData icon;
  final String? path; // for direct items (and the group "home")
  final List<NavGroupChild> children;

  /// Backend module keys that make this entry visible. A group lists every key
  /// its children use, so the parent disappears only when all of them do.
  final List<String> modules;
  const NavEntry({
    required this.key,
    required this.label,
    required this.icon,
    this.path,
    this.children = const [],
    this.modules = const [],
  });

  bool get isGroup => children.isNotEmpty;

  /// Where tapping this entry actually goes — its own path, or its first
  /// child's when it is a path-less group (People, Training).
  String? get landingPath => path ?? (children.isNotEmpty ? children.first.path : null);
}

/// The app's top-level sections, in the order the drawer renders them. The
/// single source of truth for both [AppDrawer] and the router's post-login
/// landing screen — a module key gates the same entry the same way in both
/// places, so a role's first screen is always one it can also see in the menu.
const List<NavEntry> navCatalog = [
  NavEntry(
      key: 'dashboard',
      label: 'Dashboard',
      icon: PhosphorIconsRegular.layout,
      path: Routes.dashboard,
      modules: ['dashboard']),
  NavEntry(
      key: 'crm',
      label: 'CRM',
      icon: PhosphorIconsRegular.usersThree,
      path: Routes.home,
      modules: [
        'lead',
        'customer',
        'quotation',
        'payment',
        'task',
        'followup',
        'contact',
        'call_log',
      ],
      children: [
        NavGroupChild('Customers', Routes.customers, modules: ['customer']),
        NavGroupChild('Quotes', Routes.quotes, modules: ['quotation']),
        NavGroupChild('Payments', Routes.payments, modules: ['payment']),
      ]),
  NavEntry(
      key: 'ops',
      label: 'Operations',
      icon: PhosphorIconsRegular.kanban,
      path: Routes.opsHome,
      modules: ['project', 'project_task']),
  NavEntry(
      key: 'helpdesk',
      label: 'Helpdesk',
      icon: PhosphorIconsRegular.headset,
      path: Routes.helpHome,
      modules: ['issue']),
  NavEntry(
      key: 'rewards',
      label: 'My Rewards',
      icon: PhosphorIconsRegular.trophy,
      path: Routes.rewards,
      modules: ['milestone']),
  NavEntry(
      key: 'training',
      label: 'Training',
      icon: PhosphorIconsRegular.graduationCap,
      modules: ['course', 'lms_module', 'quiz', 'course_enrollment'],
      children: [
        NavGroupChild('Overview', Routes.lmsOverview, modules: ['course']),
        NavGroupChild('Learners', Routes.lmsLearners, modules: ['course_enrollment']),
        NavGroupChild('My courses', Routes.lmsMy, modules: ['course_enrollment']),
      ]),
  NavEntry(
      key: 'products',
      label: 'Products',
      icon: PhosphorIconsRegular.package,
      path: Routes.products,
      modules: ['product']),
  NavEntry(
      key: 'users',
      label: 'People',
      icon: PhosphorIconsRegular.users,
      modules: ['user_management', 'team', 'role'],
      children: [
        NavGroupChild('Members', Routes.members, modules: ['user_management']),
        NavGroupChild('Teams', Routes.teams, modules: ['team']),
        NavGroupChild('Roles & permissions', Routes.roles, modules: ['role']),
      ]),
  NavEntry(
      key: 'reports',
      label: 'Reports',
      icon: PhosphorIconsRegular.chartBar,
      path: Routes.reports,
      modules: ['report']),
  NavEntry(
      key: 'billing',
      label: 'Billing',
      icon: PhosphorIconsRegular.creditCard,
      path: Routes.billing,
      // An org-level, admin-only screen — subscription/plan/storage, the same
      // class as Settings and the admin Dashboard per permissions.md — not the
      // CRM `payment` module a plain CRM User already has.
      modules: ['settings']),
];

/// The first screen a signed-in user should actually land on.
///
/// [access] is `null` while it hasn't loaded yet, or for mock mode / a failed
/// fetch — in every one of those cases the Dashboard is still the honest
/// default (the network blip philosophy in [ModuleAccess] applies here too:
/// we don't know the role, so we don't guess it away from Dashboard). Once
/// access is known, this walks [navCatalog] in the same order the drawer
/// renders it and returns the first entry the role can actually see — the
/// same rule twice guarantees a user's landing screen is always something
/// their own menu also offers, so they never land somewhere blocked.
String landingPathFor(ModuleAccess? access) {
  if (access == null) return Routes.dashboard;
  for (final e in navCatalog) {
    if (access.canAny(e.modules)) {
      final path = e.landingPath;
      if (path != null) return path;
    }
  }
  // A role with no readable module at all still needs somewhere to sit;
  // Dashboard's own "No access" retry state is a better dead end than a
  // router loop with nowhere to resolve to.
  return Routes.dashboard;
}
