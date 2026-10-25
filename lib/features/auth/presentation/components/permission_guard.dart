import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/module_perm_providers.dart';

/// A write verb a control needs on a module.
enum PermVerb { create, update, delete, approve }

/// Whether the signed-in role holds [verb] on [module].
bool hasPermission(WidgetRef ref, String module, PermVerb verb) {
  final p = ref.read(modulePermProvider(module));
  return switch (verb) {
    PermVerb.create => p.create,
    PermVerb.update => p.update,
    PermVerb.delete => p.delete,
    PermVerb.approve => p.approve,
  };
}

/// The mobile twin of the webapp's disabled `PermissionGate`: the control
/// stays where it is, and tapping it without the grant says why (the webapp's
/// tooltip copy) instead of opening a form the server will refuse.
/// Returns whether the action may go ahead.
bool ensurePermission(WidgetRef ref, String module, PermVerb verb) {
  if (hasPermission(ref, module, verb)) return true;
  ref.read(toastProvider.notifier).showError(permissionCopy(verb));
  return false;
}

/// The webapp's reason text for a missing [verb] — a disabled menu row's
/// sublabel.
String permissionCopy(PermVerb verb) => switch (verb) {
      PermVerb.create => PermissionCopy.create,
      PermVerb.update => PermissionCopy.update,
      PermVerb.delete => PermissionCopy.delete,
      PermVerb.approve => PermissionCopy.approve,
    };
