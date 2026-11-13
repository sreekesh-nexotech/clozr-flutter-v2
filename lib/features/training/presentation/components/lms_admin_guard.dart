import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../../auth/domain/entities/module_access.dart';
import '../lms_nav.dart';
import 'lms_header.dart';

/// Whether [access] may open the admin Training surfaces (Training Dashboard,
/// Course builder, Learners, course / learner detail). Webapp shellGating:
/// `staffHidden` entries need the LMS `course` module; System Admins always
/// pass. Unknown access (mock mode, a failed fetch) is not gated — the server
/// still refuses per request.
bool canManageCourses(ModuleAccess? access) =>
    access == null ||
    access.isStaff ||
    access.isSuperuser ||
    access.can('course');

/// Webapp `TrainingAdminGuard`: a learner without course-management access
/// gets the "Course management is admin-only" panel and a way to their own
/// training instead of an admin screen rendered empty. Nothing below mounts,
/// so no admin request (and no 403) is made.
class LmsAdminGuard extends ConsumerWidget {
  const LmsAdminGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(moduleAccessProvider);
    if (async.isLoading && !async.hasValue) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (canManageCourses(async.valueOrNull)) return child;
    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context, fallback: Routes.lmsMy),
            title: Text('Training', style: AppText.h1()),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: ErrorState(
                  icon: PhosphorIconsFill.lock,
                  iconColor: AppColors.textMuted,
                  iconBg: AppColors.bgLight,
                  title: 'Course management is admin-only',
                  body:
                      'Building courses and managing learners needs course-management access. '
                      'Head to your assigned training instead.',
                  ctaLabel: 'My Trainings',
                  ctaIcon: PhosphorIconsBold.graduationCap,
                  onRetry: () => context.go(Routes.lmsMy),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
