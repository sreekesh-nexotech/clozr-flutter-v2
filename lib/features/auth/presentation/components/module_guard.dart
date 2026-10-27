import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../shell/domain/nav_catalog.dart';
import '../../application/providers/auth_providers.dart';

/// Webapp `ModuleGuard`: a screen whose module the role does not include
/// shows the lock panel instead of mounting — so it fires no request and no
/// 403 toast — with a way back to the user's own landing screen.
///
/// While the role is still loading nothing is mounted either (the webapp
/// shows "Loading…"); unknown access (mock mode, a failed fetch) lets the
/// screen through, and the server still refuses per request.
class ModuleGuard extends ConsumerWidget {
  const ModuleGuard({super.key, required this.module, required this.child, this.anyOf = const []});

  final String module;
  final Widget child;

  /// Extra module keys that also open the screen — a section landing page
  /// (Operations home) serves a role holding either of its modules.
  final List<String> anyOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(moduleAccessProvider);
    if (async.isLoading && !async.hasValue) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final access = async.valueOrNull;
    if (access == null || access.can(module) || anyOf.any(access.can)) return child;
    return ColoredBox(
      color: AppColors.bgScreen,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ErrorState(
              icon: PhosphorIconsFill.lock,
              iconColor: AppColors.textMuted,
              iconBg: AppColors.bgLight,
              title: "You don't have access to this area",
              body: "Your role doesn't include this module. If you think this is a "
                  'mistake, ask a workspace admin to grant it.',
              ctaLabel: 'Go to dashboard',
              ctaIcon: PhosphorIconsBold.house,
              onRetry: () => context.go(landingPathFor(access)),
            ),
          ),
        ),
      ),
    );
  }
}
