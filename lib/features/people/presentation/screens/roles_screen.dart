import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/people_providers.dart';
import '../../domain/entities/role.dart';
import '../components/info_banner.dart';
import '../components/people_title_actions.dart';
import '../components/role_card.dart';
import '../sheets/add_role_sheet.dart';

/// Roles & permissions — the predefined (locked) roles, each with a fixed
/// capability matrix and one visibility scope. Header (brand + title + add) over
/// a scrolling list led by an info banner.
class RolesScreen extends ConsumerWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Contextual add: the bottom-nav `+` opens the Add role sheet here.
    registerAdd(
      ref,
      AddAction(label: 'Add role', run: (ctx) => showAddRoleSheet(ctx)),
    );

    final rolesAsync = ref.watch(rolesProvider);

    void toast(String m) => ref.read(toastProvider.notifier).show(m);

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
                Expanded(child: Text('Roles & permissions', style: AppText.screenTitle())),
                PeopleCreateButton(label: 'Add role', onTap: () => showAddRoleSheet(context)),
              ],
            ),
            SizedBox(height: 6.h),
            Text(
              'Who sees what — predefined roles are locked; extend access with custom roles.',
              style: AppText.caption(),
            ),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<Role>>(
            value: rolesAsync,
            onRetry: () => ref.invalidate(rolesProvider),
            data: (roles) {
              final members = ref.watch(membersProvider).valueOrNull ?? const [];
              return ListView(
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                children: [
                  const InfoBanner(
                    spans: [
                      TextSpan(text: 'Predefined roles have a '),
                      TextSpan(text: 'fixed capability matrix and one visibility scope each', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: '. Settings, Integrations & Billing stay with the System Admin.'),
                    ],
                  ),
                  if (roles.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 10.h),
                      child: EmptyState(
                        icon: PhosphorIconsRegular.shieldCheck,
                        title: 'No roles yet',
                        body: 'Roles decide who sees what. Add a custom role to extend access beyond the predefined ones.',
                        ctaLabel: 'Add role',
                        ctaIcon: PhosphorIconsBold.plus,
                        onCta: () => showAddRoleSheet(context),
                      ),
                    )
                  else
                    for (final role in roles) ...[
                      SizedBox(height: 10.h),
                      RoleCard(
                        role: role,
                        memberCount: members.where((m) => m.role == role.name).length,
                        onTap: () => toast(role.locked ? 'Seeded roles are read-only' : 'Edit role — coming soon'),
                        onDelete: role.locked ? null : () => toast('Delete role — coming soon'),
                      ),
                    ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
