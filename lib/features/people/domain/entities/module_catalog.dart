import 'package:equatable/equatable.dart';

/// The visibility labels this app shows for the API's record-scope codes.
///
/// The catalog serves its own labels ("All Records", "Hierarchy Records"), but
/// the role cards have always read "Organization-wide" / "Self + Reporting
/// Hierarchy". Both surfaces describe the same stored value, so they share one
/// vocabulary here rather than disagreeing depending on which screen you are on.
/// A code this map does not know keeps whatever label the server gave it.
const kRoleScopeLabels = <String, String>{
  'all': 'Organization-wide',
  'hierarchy': 'Self + Reporting Hierarchy',
  'team': 'Team-based + Reporting Hierarchy',
  'owned': 'Owned Records',
  'assignee': 'Assigned Records',
  'filtered': 'Filtered Records',
};

/// One grantable capability card — a business module group (`crm`, `pmo`).
class RoleModuleGroup extends Equatable {
  const RoleModuleGroup({
    required this.key,
    required this.label,
    this.description = '',
    this.comingSoon = false,
  });

  /// The value `module_groups[].group` is written as.
  final String key;
  final String label;
  final String description;

  /// Groups the backend has not shipped yet. Rendered locked: granting one is
  /// rejected on create (`roles.md` §3).
  final bool comingSoon;

  @override
  List<Object?> get props => [key, label, description, comingSoon];
}

/// One record-visibility scope a grant can carry.
class RoleVisibilityScope extends Equatable {
  const RoleVisibilityScope({required this.value, required this.label});

  /// The value `module_groups[].visibility` is written as.
  final String value;

  /// The server's own label, used only when [kRoleScopeLabels] has no entry.
  final String label;

  String get displayLabel => kRoleScopeLabels[value] ?? label;

  @override
  List<Object?> get props => [value, label];
}

/// `GET /management/permissions/module-catalog/` — what the Add role form
/// offers: one capability card per module group, and the visibility scopes a
/// grant can carry.
class ModuleCatalog extends Equatable {
  const ModuleCatalog({this.groups = const [], this.scopes = const []});

  final List<RoleModuleGroup> groups;
  final List<RoleVisibilityScope> scopes;

  /// Unusable — nothing to render. The form falls back to [builtIn].
  bool get isEmpty => groups.isEmpty || scopes.isEmpty;

  /// What the form offers before the catalog lands, in mock mode, and when the
  /// fetch fails.
  ///
  /// Deliberately the two groups the backend documents as enabled and the three
  /// scopes the role cards already display, so a role created offline-ish is
  /// still one the server would accept.
  static const builtIn = ModuleCatalog(
    groups: [
      RoleModuleGroup(
          key: 'crm',
          label: 'CRM',
          description: 'Leads, customers, quotes & payments'),
      RoleModuleGroup(
          key: 'pmo', label: 'PMO', description: 'Projects & project tasks'),
    ],
    scopes: [
      RoleVisibilityScope(value: 'all', label: 'All Records'),
      RoleVisibilityScope(value: 'hierarchy', label: 'Hierarchy Records'),
      RoleVisibilityScope(value: 'team', label: 'Team Records'),
    ],
  );

  /// The scopes worth offering on a phone: the ones this app has a label for.
  /// `filtered` needs a filter builder the mobile form does not have, so it is
  /// dropped rather than offered as a scope that cannot be configured.
  List<RoleVisibilityScope> get offerableScopes => [
        for (final s in scopes)
          if (s.value != 'filtered' && kRoleScopeLabels.containsKey(s.value)) s,
      ];

  static ModuleCatalog fromJson(Object? body) {
    if (body is! Map) return ModuleCatalog.empty;

    final groups = <RoleModuleGroup>[];
    final rawGroups = body['groups'];
    if (rawGroups is List) {
      for (final g in rawGroups) {
        if (g is! Map) continue;
        final key = (g['key'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        final label = (g['label'] ?? '').toString().trim();
        groups.add(RoleModuleGroup(
          key: key,
          label: label.isNotEmpty ? label : key.toUpperCase(),
          description: (g['description'] ?? '').toString(),
          comingSoon: g['coming_soon'] == true,
        ));
      }
    }

    final scopes = <RoleVisibilityScope>[];
    final rawScopes = body['visibility_scopes'];
    if (rawScopes is List) {
      for (final s in rawScopes) {
        if (s is! Map) continue;
        final value = (s['value'] ?? '').toString().trim();
        if (value.isEmpty) continue;
        final label = (s['label'] ?? '').toString().trim();
        scopes.add(RoleVisibilityScope(
          value: value,
          label: label.isNotEmpty ? label : value,
        ));
      }
    }

    return ModuleCatalog(groups: groups, scopes: scopes);
  }

  static const empty = ModuleCatalog();

  @override
  List<Object?> get props => [groups, scopes];
}
