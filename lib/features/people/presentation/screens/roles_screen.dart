import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
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
            onRefresh: () => _refresh(ref),
            data: (roles) {
              final members = ref.watch(membersProvider).valueOrNull ?? const [];
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                        // Seeded roles open too — read-only, with Save greyed
                        // out. They cannot be edited (the PATCH is a 403), but
                        // the sheet is where a role's scope and capability
                        // cards are actually legible.
                        onTap: () => showEditRoleSheet(context, role),
                        onDelete: role.locked ? null : () => _confirmDelete(context, ref, role),
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

  /// Pull-to-refresh. The card counts each role's members off the roster, so
  /// both are reloaded together.
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(rolesProvider);
    ref.invalidate(membersProvider);
    await settle([
      ref.read(rolesProvider.future),
      ref.read(membersProvider.future),
    ]);
  }

  /// The card's trash icon — `DELETE /management/roles/{role_id}/`
  /// (`roles.md` §6). Deleting is irreversible, so it asks first.
  ///
  /// A role that still has members is refused server-side with a 409, because
  /// the `UserRole` FK cascades and a bare delete would strip those people of
  /// their role. `is_deletable` says so up front, so that case is answered
  /// without a round trip — and with the count, which is the actionable part.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Role role) async {
    final toast = ref.read(toastProvider.notifier);
    if (!role.deletable) {
      final n = role.userCount;
      toast.showError(n > 0
          ? 'Reassign the $n member${n == 1 ? '' : 's'} on "${role.name}" before deleting it.'
          : 'This role cannot be deleted.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete role?'),
        content: Text(
          '"${role.name}" will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(peopleRepositoryProvider).deleteRole(role.id);
    } on AppError catch (e) {
      // The 409 carries its own sentence naming the member count, and the 403
      // says the role is seeded — both are better than anything invented here.
      toast.showError(e.message);
      // Someone may have been assigned since the list loaded, which is exactly
      // what the refusal means; refetch so the card stops offering it.
      ref.invalidate(rolesProvider);
      return;
    }
    ref.invalidate(rolesProvider);
    // A deleted role frees its members, whose cards name the role they hold.
    ref.invalidate(membersProvider);
    toast.show('Role "${role.name}" deleted');
  }
}
