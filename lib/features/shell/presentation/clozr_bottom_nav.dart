import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../application/providers/contextual_add_provider.dart';

/// A single tab spec.
class _NavItem {
  final String key;
  final String label;
  final IconData regular;
  final IconData fill;
  final String path;
  final double width;
  const _NavItem(this.key, this.label, this.regular, this.fill, this.path, this.width);
}

/// The frosted-glass bottom navigation. Its item set switches by [NavContext]
/// (CRM / Operations / Helpdesk / Dashboard) exactly like the prototype.
class ClozrBottomNav extends ConsumerWidget {
  const ClozrBottomNav({super.key, required this.location});

  final String location;

  NavContext get _ctx => Routes.metaFor(location).nav;

  List<_NavItem> get _items {
    switch (_ctx) {
      case NavContext.ops:
        return [
          _NavItem('home', 'Home', PhosphorIconsRegular.house, PhosphorIconsFill.house, Routes.opsHome, 46),
          _NavItem('projects', 'Projects', PhosphorIconsRegular.briefcase, PhosphorIconsFill.briefcase, Routes.opsProjects, 54),
          _NavItem('tasks', 'Tasks', PhosphorIconsRegular.listChecks, PhosphorIconsFill.listChecks, Routes.opsTasks, 46),
        ];
      case NavContext.help:
        return [
          _NavItem('home', 'Home', PhosphorIconsRegular.house, PhosphorIconsFill.house, Routes.helpHome, 46),
          _NavItem('tickets', 'Tickets', PhosphorIconsRegular.ticket, PhosphorIconsFill.ticket, Routes.tickets, 46),
          _NavItem('boards', 'Boards', PhosphorIconsRegular.kanban, PhosphorIconsFill.kanban, Routes.helpBoards, 46),
        ];
      case NavContext.dash:
        return [
          _NavItem('business', 'Business', PhosphorIconsRegular.chartPieSlice, PhosphorIconsFill.chartPieSlice, Routes.dashboard, 64),
          _NavItem('crm', 'CRM', PhosphorIconsRegular.usersThree, PhosphorIconsFill.usersThree, '${Routes.dashboard}?tab=crm', 64),
          _NavItem('ops', 'Operations', PhosphorIconsRegular.briefcase, PhosphorIconsFill.briefcase, '${Routes.dashboard}?tab=ops', 64),
          _NavItem('help', 'Helpdesk', PhosphorIconsRegular.headset, PhosphorIconsFill.headset, '${Routes.dashboard}?tab=help', 64),
        ];
      case NavContext.crm:
      case NavContext.none:
        return [
          _NavItem('home', 'Home', PhosphorIconsRegular.house, PhosphorIconsFill.house, Routes.home, 46),
          _NavItem('leads', 'Leads', PhosphorIconsRegular.users, PhosphorIconsFill.users, Routes.leads, 46),
          _NavItem('followups', 'Follow-ups', PhosphorIconsRegular.clock, PhosphorIconsFill.clock, Routes.followups, 54),
          _NavItem('tasks', 'Tasks', PhosphorIconsRegular.listDashes, PhosphorIconsFill.listDashes, Routes.tasks, 46),
        ];
    }
  }

  bool get _hasAdd => _ctx != NavContext.dash;

  /// Location-aware fallback route for the `+` when the current screen has not
  /// registered a contextual add action (#10/#14).
  String get _fallbackAddPath {
    final path = location.split('?').first;
    if (path.startsWith('/ops/projects')) return Routes.createProject;
    if (path.startsWith('/ops')) return Routes.createTask;
    if (path.startsWith('/help')) return Routes.createTicket;
    if (path.startsWith('/quotes')) return Routes.addQuote;
    return Routes.addLead;
  }

  bool _isActive(_NavItem it) {
    final path = location.split('?').first;
    if (_ctx == NavContext.dash) {
      final tab = Uri.parse(location).queryParameters['tab'] ?? 'business';
      return it.key == tab;
    }
    switch (it.key) {
      case 'home':
        return path == Routes.home || path == Routes.opsHome || path == Routes.helpHome;
      case 'leads':
        return path.startsWith('/leads');
      case 'followups':
        return path.startsWith('/followups');
      case 'tasks':
        return path == Routes.tasks || path == Routes.taskDetail;
      case 'projects':
        return path.startsWith('/ops/projects');
      case 'tickets':
        return path.startsWith('/help/tickets');
      case 'boards':
        return path == Routes.helpBoards;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Two-layer frosted stack (#1): an 88px strip that heavily blurs whatever
    // scrolls beneath it — strongest across its full height from the top edge
    // down — with a floating rounded pill that adds its own stronger blur so it
    // reads as a distinct frosted-glass card rather than a flat bar.
    return SizedBox(
      height: 88.h,
      child: Stack(
        children: [
          // Outer blur strip.
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                child: Container(color: const Color(0xFFF9FAFB).withOpacity(0.72)),
              ),
            ),
          ),
          // Floating frosted pill.
          Padding(
            padding: EdgeInsets.only(top: 8.h, left: 14.w, right: 14.w),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14.r),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 52, sigmaY: 52),
                child: Container(
                  height: 64.h,
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.66),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(
                        color: const Color(0xFFD2D4DA).withOpacity(0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF101828).withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final it in _items) _tab(context, it),
                      if (_hasAdd) _addButton(context, ref),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, _NavItem it) {
    final on = _isActive(it);
    final color = on ? AppColors.navy : AppColors.textPlaceholder;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        if (location.split('?').first != it.path.split('?').first || _ctx == NavContext.dash) {
          context.go(it.path);
        }
      },
      child: SizedBox(
        width: it.width.w,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22.w,
              height: 3.h,
              margin: EdgeInsets.only(bottom: 5.h),
              decoration: BoxDecoration(
                color: on ? AppColors.navy : Colors.transparent,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            Icon(on ? it.fill : it.regular, size: 22.sp, color: color),
            SizedBox(height: 4.h),
            Text(
              it.label,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 10.5.sp,
                height: 1,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addButton(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        // Prefer the current screen's registered add action (#14); otherwise
        // fall back to a location-aware route.
        final action = ref.read(contextualAddProvider);
        if (action != null) {
          action.run(context);
        } else {
          context.push(_fallbackAddPath);
        }
      },
      child: Container(
        width: 46.w,
        height: 46.w,
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(13.r),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withOpacity(0.30),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(PhosphorIconsBold.plus, size: 21.sp, color: AppColors.white),
      ),
    );
  }
}
