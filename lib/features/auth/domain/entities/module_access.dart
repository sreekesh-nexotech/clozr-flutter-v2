import 'package:equatable/equatable.dart';

/// One module's CRUD grants. Presence of the module key is what gates a nav
/// entry; these flags gate the buttons inside it.
class ModulePermission extends Equatable {
  const ModulePermission({
    this.label = '',
    this.canRead = false,
    this.canCreate = false,
    this.canUpdate = false,
    this.canDelete = false,
    this.canExport = false,
    this.canImport = false,
    this.canApprove = false,
  });

  final String label;
  final bool canRead;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;
  final bool canExport;
  final bool canImport;
  final bool canApprove;

  factory ModulePermission.fromJson(Map<String, dynamic> json) =>
      ModulePermission(
        label: json['label'] as String? ?? '',
        canRead: json['can_read'] == true,
        canCreate: json['can_create'] == true,
        canUpdate: json['can_update'] == true,
        canDelete: json['can_delete'] == true,
        canExport: json['can_export'] == true,
        canImport: json['can_import'] == true,
        canApprove: json['can_approve'] == true,
      );

  @override
  List<Object?> get props => [label, canRead, canCreate, canUpdate, canDelete];
}

/// `GET /auth/me/modules/` — the effective module-access map for the signed-in
/// user, and the source of truth for which nav entries render.
///
/// Only modules the user can at least read are present, so a missing key means
/// "no access — don't render it" (see `docs-flutter/permissions.md`). The
/// backend already applies the admin/Executive-Leadership overlays, so the app
/// reads the result rather than re-deriving it from role names.
class ModuleAccess extends Equatable {
  const ModuleAccess({
    this.isStaff = false,
    this.isSuperuser = false,
    this.fullAccess = false,
    this.hasSubordinates = false,
    this.roles = const [],
    this.modules = const {},
    this.sidebar = const [],
  });

  final bool isStaff;
  final bool isSuperuser;
  final bool fullAccess;

  /// The user manages at least one person — gates "My Team" surfaces.
  final bool hasSubordinates;

  /// Role names, highest privilege first. Display only — never gate on these.
  final List<String> roles;

  final Map<String, ModulePermission> modules;

  /// The module keys in nav order, as the backend sorted them.
  final List<String> sidebar;

  /// Whether [key] is readable at all.
  bool can(String key) => modules.containsKey(key);

  /// Whether any of [keys] is readable. An empty list means "not gated".
  bool canAny(Iterable<String> keys) => keys.isEmpty || keys.any(can);

  factory ModuleAccess.fromJson(Map<String, dynamic> json) {
    final raw = json['modules'];
    return ModuleAccess(
      isStaff: json['is_staff'] == true,
      isSuperuser: json['is_superuser'] == true,
      fullAccess: json['full_access'] == true,
      hasSubordinates: json['has_subordinates'] == true,
      roles: (json['roles'] as List? ?? const []).whereType<String>().toList(),
      modules: raw is Map
          ? {
              for (final entry in raw.entries)
                if (entry.key is String && entry.value is Map)
                  entry.key as String: ModulePermission.fromJson(
                      Map<String, dynamic>.from(entry.value as Map)),
            }
          : const {},
      sidebar:
          (json['sidebar'] as List? ?? const []).whereType<String>().toList(),
    );
  }

  @override
  List<Object?> get props => [fullAccess, hasSubordinates, roles, modules, sidebar];
}
