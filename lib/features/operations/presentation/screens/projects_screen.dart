import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/projects_providers.dart';
import '../components/ops_widgets.dart';
import '../components/project_card.dart';

/// Projects list — status tabs + a "My Projects" saved-view chip over a
/// scrolling list of project cards.
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(projSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ref.watch(projBaseProvider);
    final visible = ref.watch(visibleProjectsProvider);
    final tab = ref.watch(projTabProvider);
    final mine = ref.watch(myProjectsProvider);
    final searchOpen = ref.watch(projSearchOpenProvider);
    final query = ref.watch(projSearchProvider);

    final tabDefs = <(String, String)>[
      ('all', 'All'),
      for (final k in StatusMeta$.project.keys) (k, StatusMeta$.project[k]!.label),
    ];

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            Row(
              children: [
                Expanded(child: Text('Projects', style: AppText.screenTitle())),
                _iconAction(
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  dot: query.isNotEmpty,
                  onTap: () => ref.read(projSearchOpenProvider.notifier).state = !searchOpen,
                ),
                _iconAction(
                  icon: PhosphorIconsRegular.slidersHorizontal,
                  onTap: () => ref.read(toastProvider.notifier).show('Filters — full project filter engine'),
                ),
                SizedBox(width: 4.w),
                GestureDetector(
                  onTap: () => context.push(Routes.createProject),
                  child: Container(
                    width: 38.w,
                    height: 38.w,
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(10.r)),
                    child: Icon(PhosphorIconsBold.plus, size: 18.sp, color: AppColors.white),
                  ),
                ),
              ],
            ),
            if (searchOpen) ...[
              SizedBox(height: 12.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search projects…',
                onChanged: (v) => ref.read(projSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(projSearchProvider.notifier).state = '';
                  ref.read(projSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 12.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final (k, label) in tabDefs)
                    TabChip(
                      label: '$label (${projTabCount(base, k, mine: mine)})',
                      active: tab == k,
                      onTap: () => ref.read(projTabProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                OpsSavedChip(
                  label: 'My Projects',
                  active: mine,
                  onTap: () => ref.read(myProjectsProvider.notifier).state = !mine,
                ),
              ],
            ),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: visible.isEmpty
              ? ListView(
                  children: const [
                    EmptyState(
                      icon: PhosphorIconsRegular.briefcase,
                      title: 'No projects found',
                      body: 'Try a different status, or turn off "My Projects" to see the whole portfolio.',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => SizedBox(height: 12.h),
                  itemBuilder: (context, i) {
                    final p = visible[i];
                    return ProjectCard(
                      project: p,
                      onTap: () => context.push('${Routes.projectDetail}?id=${p.id}'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _iconAction({required IconData icon, required VoidCallback onTap, bool dot = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 38.w,
        height: 38.w,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 20.sp, color: AppColors.textSecondary),
            if (dot)
              Positioned(
                top: 7.h,
                right: 7.w,
                child: Container(
                  width: 7.w,
                  height: 7.w,
                  decoration: BoxDecoration(
                    color: AppColors.blueBright,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
