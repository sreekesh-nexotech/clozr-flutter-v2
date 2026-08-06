import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../data/mock/mock_users.dart';
import '../../domain/entities/crm_catalog.dart';

/// Picks the lead's new owner from the users the server says are eligible.
///
/// [users] is fetched before the sheet opens rather than inside it: the list is
/// the whole content, so opening onto a spinner and then reflowing is worse
/// than the brief wait, and a half-loaded list could be tapped.
///
/// [currentOwnerId] is the id the lead reports — which may be the `'me'`
/// sentinel, so it is compared through [UserDirectory.mapUserId] rather than
/// against the raw uuid.
///
/// Returns the chosen `user_id`, or null if dismissed.
Future<String?> showReassignOwnerSheet({
  required BuildContext context,
  required List<CatalogOption> users,
  required String currentOwnerId,
}) {
  return showClozrSheet<String>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Reassign owner', onClose: () => Navigator.of(ctx).pop()),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
            children: [
              for (final u in users)
                _OwnerRow(
                  user: u,
                  selected: UserDirectory.mapUserId(u.id) == currentOwnerId,
                  onTap: () => Navigator.of(ctx).pop(u.id),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _OwnerRow extends StatelessWidget {
  const _OwnerRow({required this.user, required this.selected, required this.onTap});

  final CatalogOption user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Colour comes from the shared directory so a person looks the same here as
    // in the avatars on the lead itself.
    final known = MockUsers.of(UserDirectory.mapUserId(user.id));
    final initials = UserDirectory.initialsOf(user.name);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF6F8FB) : Colors.transparent,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Container(
              width: 34.w,
              height: 34.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: known.color, shape: BoxShape.circle),
              child: Text(
                initials,
                style: AppText.custom(
                    size: 12.5, weight: FontWeight.w700, color: AppColors.white),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(child: Text(user.name, style: AppText.bodyStrong())),
            if (selected)
              Icon(PhosphorIconsBold.check, size: 18.sp, color: AppColors.success),
          ],
        ),
      ),
    );
  }
}
