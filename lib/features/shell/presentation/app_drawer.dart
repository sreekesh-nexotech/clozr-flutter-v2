import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../app/config/constants.dart';
import '../../../app/router/routes.dart';
import '../../../core/config/api_config.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../data/api/user_directory.dart';
import '../../auth/application/providers/auth_providers.dart';
import '../application/providers/shell_providers.dart';

/// Shown until `/me` resolves and in mock mode, where there is no session —
/// keeps the prototype build reading exactly as it did.
const _seedName = 'Manoj Varma';
const _seedInitials = 'MV';
const _seedRole = 'System Admin';
const _seedWorkspaceSub = 'Clozr workspace';

class _NavGroupChild {
  final String label;
  final String path;

  /// Backend module keys (`docs-flutter/permissions.md`) that make this row
  /// visible. Empty = never gated.
  final List<String> modules;
  const _NavGroupChild(this.label, this.path, {this.modules = const []});
}

class _NavEntry {
  final String key;
  final String label;
  final IconData icon;
  final String? path; // for direct items (and the group "home")
  final List<_NavGroupChild> children;

  /// Backend module keys that make this entry visible. A group lists every key
  /// its children use, so the parent disappears only when all of them do.
  final List<String> modules;
  const _NavEntry({
    required this.key,
    required this.label,
    required this.icon,
    this.path,
    this.children = const [],
    this.modules = const [],
  });

  bool get isGroup => children.isNotEmpty;
}

/// Left module drawer (312px). Mirrors the prototype's sidebar structure.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, required this.location});

  final String location;

  static final List<_NavEntry> _entries = [
    _NavEntry(
        key: 'dashboard',
        label: 'Dashboard',
        icon: PhosphorIconsRegular.layout,
        path: Routes.dashboard,
        modules: const ['dashboard']),
    _NavEntry(
        key: 'crm',
        label: 'CRM',
        icon: PhosphorIconsRegular.usersThree,
        path: Routes.home,
        modules: const [
          'lead',
          'customer',
          'quotation',
          'payment',
          'task',
          'followup',
          'contact',
          'call_log',
        ],
        children: const [
          _NavGroupChild('Customers', Routes.customers, modules: ['customer']),
          _NavGroupChild('Quotes', Routes.quotes, modules: ['quotation']),
          _NavGroupChild('Payments', Routes.payments, modules: ['payment']),
        ]),
    _NavEntry(
        key: 'ops',
        label: 'Operations',
        icon: PhosphorIconsRegular.kanban,
        path: Routes.opsHome,
        modules: const ['project', 'project_task']),
    _NavEntry(
        key: 'helpdesk',
        label: 'Helpdesk',
        icon: PhosphorIconsRegular.headset,
        path: Routes.helpHome,
        modules: const ['issue']),
    _NavEntry(
        key: 'rewards',
        label: 'My Rewards',
        icon: PhosphorIconsRegular.trophy,
        path: Routes.rewards,
        modules: const ['milestone']),
    _NavEntry(
        key: 'training',
        label: 'Training',
        icon: PhosphorIconsRegular.graduationCap,
        modules: const ['course', 'lms_module', 'quiz', 'course_enrollment'],
        children: const [
          _NavGroupChild('Overview', Routes.lmsOverview, modules: ['course']),
          _NavGroupChild('Learners', Routes.lmsLearners,
              modules: ['course_enrollment']),
          _NavGroupChild('My courses', Routes.lmsMy,
              modules: ['course_enrollment']),
        ]),
    _NavEntry(
        key: 'products',
        label: 'Products',
        icon: PhosphorIconsRegular.package,
        path: Routes.products,
        modules: const ['product']),
    _NavEntry(
        key: 'users',
        label: 'People',
        icon: PhosphorIconsRegular.users,
        modules: const ['user_management', 'team', 'role'],
        children: const [
          _NavGroupChild('Members', Routes.members,
              modules: ['user_management']),
          _NavGroupChild('Teams', Routes.teams, modules: ['team']),
          _NavGroupChild('Roles & permissions', Routes.roles,
              modules: ['role']),
        ]),
    _NavEntry(
        key: 'reports',
        label: 'Reports',
        icon: PhosphorIconsRegular.chartBar,
        path: Routes.reports,
        modules: const ['report']),
    _NavEntry(
        key: 'billing',
        label: 'Billing',
        icon: PhosphorIconsRegular.creditCard,
        path: Routes.billing,
        modules: const ['payment']),
  ];

  void _close(WidgetRef ref) => ref.read(drawerOpenProvider.notifier).state = false;

  void _navigate(BuildContext context, WidgetRef ref, String path) {
    _close(ref);
    context.go(path);
  }

  bool _childActive(String path) => location.split('?').first == path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(drawerExpandedProvider);
    // Null until /auth/me/modules/ resolves (and always in mock mode), which
    // `canAny` treats as "not gated" — the menu never collapses on a blip.
    final access = ref.watch(moduleAccessProvider).asData?.value;
    bool visible(List<String> modules) =>
        access == null || access.canAny(modules);

    return Stack(
      children: [
        // Scrim
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _close(ref),
            child: Container(color: AppColors.scrim),
          ),
        ),
        // Panel
        Positioned(
          top: 0,
          left: 0,
          bottom: 0,
          width: 312.w,
          child: Material(
            color: AppColors.white,
            child: Column(
              children: [
                _header(ref),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(4.w, 0, 4.w, 10.h),
                        child: Text('Menu',
                            style: AppText.custom(
                                size: 11,
                                weight: FontWeight.w700,
                                color: AppColors.textPlaceholder,
                                letterSpacing: 0.6)),
                      ),
                      for (final e in _entries)
                        if (visible(e.modules))
                          ..._row(context, ref, e, expanded, visible),
                    ],
                  ),
                ),
                _footer(ref),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(WidgetRef ref) {
    final org = ref.watch(sessionControllerProvider).user?.primaryOrg;
    final workspace = (org != null && org.name.isNotEmpty)
        ? org.name
        : AppConstants.workspaceName;
    final workspaceSub = (org != null && org.subdomain.isNotEmpty)
        ? org.subdomain
        : _seedWorkspaceSub;

    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 56.h, 18.w, 16.h),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          Container(
            width: 44.w,
            height: 44.w,
            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(13.r)),
            child: Icon(PhosphorIconsFill.buildings, size: 22.sp, color: AppColors.white),
          ),
          SizedBox(width: 11.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(workspace,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 16, weight: FontWeight.w800, color: AppColors.textPrimary)),
                Text(workspaceSub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.captionStrong(color: AppColors.textPlaceholder)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _close(ref),
            child: Container(
              width: 32.w,
              height: 32.w,
              decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(9.r)),
              child: Icon(PhosphorIconsBold.x, size: 15.sp, color: AppColors.textLabelAlt),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _row(
    BuildContext context,
    WidgetRef ref,
    _NavEntry e,
    Map<String, bool> expanded,
    bool Function(List<String>) visible,
  ) {
    final open = expanded[e.key] ?? false;
    final children = e.children.where((c) => visible(c.modules)).toList();
    final anyChildActive =
        children.any((c) => _childActive(c.path)) || (e.path != null && _childActive(e.path!));
    final active = anyChildActive;
    // Gated against the *visible* children: a group whose rows are all hidden
    // stops behaving like a group (no caret, no expand).
    final isGroup = children.isNotEmpty;

    final rows = <Widget>[
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (isGroup && e.path == null) {
            ref.read(drawerExpandedProvider.notifier).update((m) => {...m, e.key: !open});
          } else if (isGroup && e.path != null) {
            ref.read(drawerExpandedProvider.notifier).update((m) => {...m, e.key: true});
            _navigate(context, ref, e.path!);
          } else {
            _navigate(context, ref, e.path!);
          }
        },
        child: Container(
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: active ? AppColors.blueSubtle : Colors.transparent,
            borderRadius: BorderRadius.circular(11.r),
          ),
          child: Row(
            children: [
              Icon(e.icon, size: 19.sp, color: active ? AppColors.navy : AppColors.textLabelAlt),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(e.label,
                    style: AppText.custom(
                        size: 14.5,
                        weight: active ? FontWeight.w700 : FontWeight.w600,
                        color: active ? AppColors.navy : AppColors.textSecondary)),
              ),
              if (isGroup)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      ref.read(drawerExpandedProvider.notifier).update((m) => {...m, e.key: !open}),
                  child: Icon(open ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
                      size: 12.sp, color: anyChildActive ? AppColors.navy : AppColors.textPlaceholder),
                ),
            ],
          ),
        ),
      ),
    ];

    if (isGroup && open) {
      for (final c in children) {
        final childActive = _childActive(c.path);
        rows.add(GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _navigate(context, ref, c.path),
          child: Container(
            height: 40.h,
            margin: EdgeInsets.only(top: 2.h),
            padding: EdgeInsets.only(left: 43.w, right: 12.w),
            decoration: BoxDecoration(
              color: childActive ? AppColors.blueSubtle : Colors.transparent,
              borderRadius: BorderRadius.circular(10.r),
            ),
            alignment: Alignment.centerLeft,
            child: Text(c.label,
                style: AppText.custom(
                    size: 13.5,
                    weight: childActive ? FontWeight.w700 : FontWeight.w500,
                    color: childActive ? AppColors.navy : AppColors.textLabel)),
          ),
        ));
      }
    }
    rows.add(SizedBox(height: 2.h));
    return rows;
  }

  Widget _footer(WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final hasName = user?.fullName.trim().isNotEmpty ?? false;
    final name = hasName ? user!.fullName : _seedName;
    final initials =
        hasName ? UserDirectory.initialsOf(user!.fullName) : _seedInitials;
    final roleLabel =
        (user?.roleLabel.isNotEmpty ?? false) ? user!.roleLabel : _seedRole;
    final avatarUrl = user?.avatarUrl ?? '';

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          _avatar(initials, avatarUrl),
          SizedBox(width: 11.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStrong().copyWith(fontWeight: FontWeight.w700)),
                Text(roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(color: AppColors.textPlaceholder)),
              ],
            ),
          ),
          _footerIcon(
            PhosphorIconsRegular.gearSix,
            AppColors.textLabelAlt,
            () {
              _close(ref);
              ref.read(toastProvider.notifier).show('Settings — coming soon');
            },
          ),
          SizedBox(width: 8.w),
          _footerIcon(
            PhosphorIconsRegular.signOut,
            AppColors.error,
            () => _signOut(ref),
          ),
        ],
      ),
    );
  }

  /// The profile picture when the account has one, initials otherwise. A broken
  /// or slow image falls back to the same initials block rather than a gap.
  Widget _avatar(String initials, String url) {
    final fallback = Container(
      width: 40.w,
      height: 40.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
      child: Text(initials,
          style: AppText.custom(
              size: 13, weight: FontWeight.w700, color: AppColors.white)),
    );
    if (url.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(11.r),
      child: Image.network(
        url,
        width: 40.w,
        height: 40.w,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }

  /// Ends the session for real: blacklists the refresh token, purges the cached
  /// tenant data and drops the gate, which sends the router to /login. Mock
  /// mode has no session to end, so it keeps the toast-only behavior.
  Future<void> _signOut(WidgetRef ref) async {
    _close(ref);
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Signed out');
      return;
    }
    // No toast and no `ref` after the await: the gate flip routes to /login,
    // which unmounts this drawer along with the toast host.
    await ref.read(sessionControllerProvider.notifier).logout();
  }

  Widget _footerIcon(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36.w,
        height: 36.w,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: AppColors.borderChip),
        ),
        child: Icon(icon, size: 17.sp, color: color),
      ),
    );
  }
}
