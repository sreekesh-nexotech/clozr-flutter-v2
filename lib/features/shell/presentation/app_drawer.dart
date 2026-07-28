import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../app/config/constants.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../application/providers/shell_providers.dart';

class _NavGroupChild {
  final String label;
  final String path;
  const _NavGroupChild(this.label, this.path);
}

class _NavEntry {
  final String key;
  final String label;
  final IconData icon;
  final String? path; // for direct items (and the group "home")
  final List<_NavGroupChild> children;
  const _NavEntry({
    required this.key,
    required this.label,
    required this.icon,
    this.path,
    this.children = const [],
  });

  bool get isGroup => children.isNotEmpty;
}

/// Left module drawer (312px). Mirrors the prototype's sidebar structure.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, required this.location});

  final String location;

  static final List<_NavEntry> _entries = [
    _NavEntry(key: 'dashboard', label: 'Dashboard', icon: PhosphorIconsRegular.layout, path: Routes.dashboard),
    _NavEntry(key: 'crm', label: 'CRM', icon: PhosphorIconsRegular.usersThree, path: Routes.home, children: const [
      _NavGroupChild('Customers', Routes.customers),
      _NavGroupChild('Quotes', Routes.quotes),
      _NavGroupChild('Payments', Routes.payments),
    ]),
    _NavEntry(key: 'ops', label: 'Operations', icon: PhosphorIconsRegular.kanban, path: Routes.opsHome),
    _NavEntry(key: 'helpdesk', label: 'Helpdesk', icon: PhosphorIconsRegular.headset, path: Routes.helpHome),
    _NavEntry(key: 'rewards', label: 'My Rewards', icon: PhosphorIconsRegular.trophy, path: Routes.rewards),
    _NavEntry(key: 'training', label: 'Training', icon: PhosphorIconsRegular.graduationCap, children: const [
      _NavGroupChild('Overview', Routes.lmsOverview),
      _NavGroupChild('Learners', Routes.lmsLearners),
      _NavGroupChild('My courses', Routes.lmsMy),
    ]),
    _NavEntry(key: 'products', label: 'Products', icon: PhosphorIconsRegular.package, path: Routes.products),
    _NavEntry(key: 'users', label: 'People', icon: PhosphorIconsRegular.users, children: const [
      _NavGroupChild('Members', Routes.members),
      _NavGroupChild('Teams', Routes.teams),
      _NavGroupChild('Roles & permissions', Routes.roles),
    ]),
    _NavEntry(key: 'reports', label: 'Reports', icon: PhosphorIconsRegular.chartBar, path: Routes.reports),
    _NavEntry(key: 'billing', label: 'Billing', icon: PhosphorIconsRegular.creditCard, path: Routes.billing),
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
                      for (final e in _entries) ..._row(context, ref, e, expanded),
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
                Text(AppConstants.workspaceName,
                    style: AppText.custom(size: 16, weight: FontWeight.w800, color: AppColors.textPrimary)),
                Text('Clozr workspace', style: AppText.captionStrong(color: AppColors.textPlaceholder)),
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

  List<Widget> _row(BuildContext context, WidgetRef ref, _NavEntry e, Map<String, bool> expanded) {
    final open = expanded[e.key] ?? false;
    final anyChildActive =
        e.children.any((c) => _childActive(c.path)) || (e.path != null && _childActive(e.path!));
    final active = anyChildActive;

    final rows = <Widget>[
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (e.isGroup && e.path == null) {
            ref.read(drawerExpandedProvider.notifier).update((m) => {...m, e.key: !open});
          } else if (e.isGroup && e.path != null) {
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
              if (e.isGroup)
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

    if (e.isGroup && open) {
      for (final c in e.children) {
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
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
            child: Text('MV',
                style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.white)),
          ),
          SizedBox(width: 11.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manoj Varma', style: AppText.bodyStrong().copyWith(fontWeight: FontWeight.w700)),
                Text('System Admin', style: AppText.caption(color: AppColors.textPlaceholder)),
              ],
            ),
          ),
          _footerIcon(ref, PhosphorIconsRegular.gearSix, AppColors.textLabelAlt),
          SizedBox(width: 8.w),
          _footerIcon(ref, PhosphorIconsRegular.signOut, AppColors.error),
        ],
      ),
    );
  }

  Widget _footerIcon(WidgetRef ref, IconData icon, Color color) {
    return GestureDetector(
      onTap: () {
        _close(ref);
        ref.read(toastProvider.notifier).show(
              icon == PhosphorIconsRegular.signOut ? 'Signed out' : 'Settings — coming soon',
            );
      },
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
