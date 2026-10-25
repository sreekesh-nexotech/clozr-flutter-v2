import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/module_access.dart';
import 'auth_providers.dart';

/// The write verbs a role holds on one module, as the webapp's
/// `useModulePermissions(module).can(verb)` reads them.
class ModulePerm {
  const ModulePerm({
    this.read = false,
    this.create = false,
    this.update = false,
    this.delete = false,
    this.approve = false,
  });

  /// Access not known yet (mock mode, a failed `/auth/me/modules/`): nothing
  /// is gated, and the server still refuses per request.
  static const open = ModulePerm(read: true, create: true, update: true, delete: true, approve: true);

  static const none = ModulePerm();

  factory ModulePerm.of(ModulePermission? p) => p == null
      ? none
      : ModulePerm(
          read: true,
          create: p.canCreate,
          update: p.canUpdate,
          delete: p.canDelete,
          approve: p.canApprove,
        );

  final bool read;
  final bool create;
  final bool update;
  final bool delete;
  final bool approve;
}

/// [ModulePerm] for one backend module key (`lead`, `task`, `followup`,
/// `customer`, `quotation`, `payment`, …). A module missing from the payload
/// is not readable at all — the webapp's `hasModule`.
final modulePermProvider = Provider.family<ModulePerm, String>((ref, module) {
  final access = ref.watch(moduleAccessProvider).valueOrNull;
  if (access == null) return ModulePerm.open;
  return ModulePerm.of(access.modules[module]);
});

/// Webapp `permissionCopy.ts` — the reason a gated control gives.
abstract final class PermissionCopy {
  static const create = "You don't have permission to add records here. Ask a workspace admin.";
  static const update = "You don't have permission to edit records here. Ask a workspace admin.";
  static const delete = "You don't have permission to delete records here. Ask a workspace admin.";
  static const approve = "You don't have permission to approve here. Ask a workspace admin.";
  static const generic = "You don't have permission to do this. Ask a workspace admin.";
}
