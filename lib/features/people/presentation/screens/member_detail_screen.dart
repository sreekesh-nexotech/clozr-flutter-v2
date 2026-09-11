import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/people_providers.dart';
import '../../domain/entities/member.dart';
import '../components/member_card.dart';
import '../sheets/edit_member_sheet.dart';

/// Member detail — profile, availability heatmap, member information (scope /
/// reporting hierarchy / team / status), performance snapshot and activity log.
class MemberDetailScreen extends ConsumerStatefulWidget {
  const MemberDetailScreen({super.key});

  @override
  ConsumerState<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  bool _infoMore = false;

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final membersAsync = ref.watch(membersProvider);
    // The enriched record once `GET /management/users/{id}/` lands, the list
    // row until then — so the page paints immediately and fills in.
    final member = ref.watch(memberDetailOrListProvider(id));

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _header(member?.name),
          Expanded(
            child: AsyncStateView<List<Member>>(
              value: membersAsync,
              onRetry: () => ref.invalidate(membersProvider),
              onRefresh: () => _refresh(id),
              loading: () => const DetailSkeleton(),
              data: (_) {
                if (member == null) {
                  return const EmptyState(
                    icon: PhosphorIconsRegular.userMinus,
                    title: 'Member not found',
                    body: 'This member may have been removed, or you may not have access to them.',
                  );
                }
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
                  children: [
                    _profileCard(member),
                    SizedBox(height: 14.h),
                    _availabilityCard(member.email),
                    SizedBox(height: 14.h),
                    _infoCard(member),
                    SizedBox(height: 14.h),
                    _performanceCard(member),
                    SizedBox(height: 14.h),
                    _activityCard(member),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Pull-to-refresh. Reloads the enriched record, the roster (for the list-row
  /// fallback), the performance card and the activity feed together.
  Future<void> _refresh(String id) async {
    ref.invalidate(membersProvider);
    ref.invalidate(memberDetailProvider(id));
    ref.invalidate(memberWithPerformanceProvider(id));
    ref.invalidate(memberActivityProvider(id));
    await settle([
      ref.read(membersProvider.future),
      ref.read(memberDetailProvider(id).future),
      ref.read(memberWithPerformanceProvider(id).future),
      ref.read(memberActivityProvider(id).future),
    ]);
  }

  Widget _header(String? name) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: DetailAppBar(
        section: 'Member',
        name: name,
        onBack: () => context.pop(),
        trailing: DetailIconAction(
          icon: PhosphorIconsBold.dotsThreeVertical,
          onTap: _openMenu,
        ),
      ),
    );
  }

  /// The overflow menu. Only Edit member for now — it is the one action
  /// `members.md` documents that the app can carry out
  /// (`PATCH /management/users/{user_id}/`).
  Future<void> _openMenu() async {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final member = ref.read(memberDetailOrListProvider(id));
    if (member == null) return;
    await showActionMenu(
      context,
      title: member.name,
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit member',
          // The API refuses edits to a protected account, so the menu says so
          // rather than opening a form that cannot save.
          enabled: !member.isProtected,
          sublabel: member.isProtected ? 'This account is protected' : null,
          onTap: () => showEditMemberSheet(context, member),
        ),
      ],
    );
  }

  // ── Profile ──
  Widget _profileCard(Member m) {
    final st = memberStatusMeta(m.status);
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(initials: m.initials, size: 54, background: AppColors.navy, fontSize: 17),
              SizedBox(width: 13.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 4.h,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(m.name,
                            style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                        StatusPill(label: st.label, color: st.color),
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Text(m.role, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              // `is_protected` — the API's own flag for an account it blocks
              // edits on. Was guessed from the role name containing "admin".
              if (m.isProtected) ...[
                SizedBox(width: 8.w),
                _protectedBadge(),
              ],
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          _contactRow(PhosphorIconsRegular.envelopeSimple, m.email, AppColors.textBody),
          SizedBox(height: 8.h),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(toastProvider.notifier).show('Calling ${m.name.split(' ').first}…'),
            child: _contactRow(PhosphorIconsRegular.phone, m.phone, AppColors.blueBright),
          ),
        ],
      ),
    );
  }

  Widget _protectedBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 4.h),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(8.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsRegular.lockSimple, size: 12.sp, color: const Color(0xFF6C6C6C)),
          SizedBox(width: 5.w),
          Text('PROTECTED',
              style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: const Color(0xFF6C6C6C), letterSpacing: 0.3)),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String text, Color textColor) {
    return Row(
      children: [
        Icon(icon, size: 16.sp, color: AppColors.textPlaceholder),
        SizedBox(width: 9.w),
        Expanded(
          child: Text(text, style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: textColor)),
        ),
      ],
    );
  }

  // ── Availability heatmap ──
  /// The heatmap is **not backed by anything** — the grid is generated from a
  /// hash of the member's email, so every square is invented. Until a leave
  /// system ships there is nothing to read it from, so the card is blurred and
  /// captioned rather than left looking like attendance data.
  ///
  /// The layout underneath is untouched: when the API lands, drop the overlay
  /// and swap [_buildMonths] for the real feed.
  Widget _availabilityCard(String email) {
    // The card itself stays crisp — only its contents blur. Blurring the whole
    // card softened its border and corners too, which read as a rendering
    // fault rather than a deliberate placeholder.
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(16.r),
      child: Stack(
        children: [
          // Inert as well as unreadable — the month strip scrolls horizontally,
          // and a blurred surface that still responds to touch feels broken.
          IgnorePointer(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: _availabilityHeatmap(email),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Attendance & leave tracking is coming soon',
                      textAlign: TextAlign.center,
                      style: AppText.custom(
                          size: 14, weight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      'A full-day/half-day/on-leave calendar will appear here once '
                      'the leave system ships.',
                      textAlign: TextAlign.center,
                      // Body-weight grey, not the muted label grey: this sits
                      // over a blurred, uneven backdrop, where #848383 was too
                      // low-contrast to read.
                      style: AppText.custom(
                          size: 12.5, weight: FontWeight.w600, color: AppColors.textBodyMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _availabilityHeatmap(String email) {
    final months = _buildMonths(email);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.calendarCheck, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Availability', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
              SizedBox(width: 6.w),
              Text('· 2026', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
            ],
          ),
          SizedBox(height: 13.h),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < months.length; i++) ...[
                  if (i > 0) SizedBox(width: 9.w),
                  _monthColumn(months[i]),
                ],
              ],
            ),
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 12.w,
            runSpacing: 8.h,
            children: [
              _legend(AppColors.success, 'Full day'),
              _legend(AppColors.warning, 'Half-day leave'),
              _legend(AppColors.error, 'On leave'),
              _legend(const Color(0xFFE8EAEE), 'Weekend'),
            ],
          ),
        ]);
  }

  Widget _monthColumn(_MonthData month) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int w = 0; w < month.weeks.length; w++) ...[
              if (w > 0) SizedBox(width: 2.w),
              Column(
                children: [
                  for (int d = 0; d < month.weeks[w].length; d++) ...[
                    if (d > 0) SizedBox(height: 2.h),
                    Container(
                      width: 9.w,
                      height: 9.w,
                      decoration: BoxDecoration(
                        color: month.weeks[w][d] ?? Colors.transparent,
                        borderRadius: BorderRadius.circular(2.5.r),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        SizedBox(height: 4.h),
        Text(month.label,
            style: AppText.custom(size: 9, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9.w, height: 9.w, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2.5.r))),
        SizedBox(width: 5.w),
        Text(label, style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
      ],
    );
  }

  /// Deterministic per-member availability grid — mirrors the prototype's
  /// seeded algorithm (weekends grey, future days faded, otherwise a pseudo-
  /// random full/half/leave day seeded off the email).
  List<_MonthData> _buildMonths(String email) {
    const labels = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    final seedN = email.codeUnits.fold<int>(0, (a, c) => a + c);
    final cutoff = DateTime(2026, 7, 9);
    return List.generate(12, (mo) {
      final dim = DateTime(2026, mo + 2, 0).day;
      final off = DateTime(2026, mo + 1, 1).weekday - 1; // Monday-first offset
      final weeks = <List<Color?>>[];
      for (int d = 1; d <= dim; d++) {
        final wk = ((d - 1 + off) / 7).floor();
        final dow = (d - 1 + off) % 7;
        while (weeks.length <= wk) {
          weeks.add(List<Color?>.filled(7, null));
        }
        final dt = DateTime(2026, mo + 1, d);
        Color bg;
        if (dt.isAfter(cutoff)) {
          bg = AppColors.bgLight; // #F3F4F5
        } else if (dow >= 5) {
          bg = const Color(0xFFE8EAEE); // weekend
        } else {
          final r = (seedN * 31 + mo * 97 + d * 13) % 100;
          bg = r < 4 ? AppColors.error : (r < 12 ? AppColors.warning : AppColors.success);
        }
        weeks[wk][dow] = bg;
      }
      return _MonthData(labels[mo], weeks);
    });
  }

  /// The short form for an IANA zone, which the API sends raw — §4.1 notes the
  /// suffix is the frontend's to render. Only the zones an Indian-market org
  /// realistically uses are named; anything else keeps its city, which is
  /// still readable ("Europe/Berlin (Berlin)").
  static String _tzAbbr(String tz) {
    const known = {
      'Asia/Kolkata': 'IST',
      'Asia/Calcutta': 'IST',
      'Asia/Dubai': 'GST',
      'UTC': 'UTC',
      'Etc/UTC': 'UTC',
    };
    final hit = known[tz];
    if (hit != null) return hit;
    final city = tz.split('/').last.replaceAll('_', ' ');
    return city.isEmpty ? tz : city;
  }

  // ── Member information ──
  Widget _infoCard(Member m) {
    // Every row is the record's own value now. Designation used to render the
    // role name, and Territory and Timezone were literals — "All India" or
    // "Kerala" off `isAdmin`, and "Asia/Kolkata (IST)" for everyone — none of
    // it fetched. All four come from `GET /management/users/{id}/` (§4.1);
    // until it lands, or where the member genuinely has none, they read "—"
    // rather than inventing a plausible answer.
    const dash = '—';
    final rows = <(String, String)>[
      ('Full name', m.name),
      ('Email', m.email),
      ('Designation', m.designation.isEmpty ? dash : m.designation),
      ('Phone', m.phone.isEmpty ? dash : m.phone),
      ('Role & scope', m.scope.isEmpty || m.scope == dash
          ? m.role
          : '${m.role} · ${m.scope}'),
      ('Reporting manager', m.hasManager ? m.reportsTo : '— (top of hierarchy)'),
      ('Team', m.hasTeam ? m.team : 'No team'),
      // Territories this user *manages*; most members manage none.
      ('Territory', m.territories.isEmpty ? dash : m.territories.join(', ')),
      ('Timezone', m.timezone.isEmpty ? dash : '${m.timezone} (${_tzAbbr(m.timezone)})'),
      ('Custom fields', 'Configured in web app'),
    ];
    final shown = _infoMore ? rows : rows.take(7).toList();
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Member information', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 6.h),
          for (final r in shown)
            Container(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.$1, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Text(r.$2,
                        textAlign: TextAlign.right,
                        style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _infoMore = !_infoMore),
            child: Padding(
              padding: EdgeInsets.only(top: 11.h, bottom: 2.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_infoMore ? 'Show less' : 'Show more',
                      style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.blueBright)),
                  SizedBox(width: 6.w),
                  Icon(_infoMore ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 12.sp, color: AppColors.blueBright),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Performance & records ──
  Widget _performanceCard(Member member) {
    // The member with their owned-lead metrics filled in. `fetchMemberPerformance`
    // and `applyPerformance` both existed but nothing ever called them, so this
    // card always rendered the entity's zero defaults — 0 / 0 / 0 / ₹0L / —.
    // Falls back to the plain member while in flight, in mock mode, and for a
    // caller without `can_access_user_kpis` (which 403s).
    final m = ref.watch(memberWithPerformanceProvider(member.id)).valueOrNull ?? member;
    final noWon = m.perfWon == 0 ? 'no won deals in range' : '';
    final noDec = m.perfClosed == 0 ? 'no decided deals in range' : '';
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.chartLineUp, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Expanded(
                child: Text('Performance & records', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              _rangeControl(),
            ],
          ),
          SizedBox(height: 14.h),
          Text('OWNED LEADS',
              style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.6)),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(child: _statTile('${m.perfOpen}', 'Open', 'in pipeline')),
              SizedBox(width: 9.w),
              Expanded(child: _statTile('${m.perfClosed}', 'Closed', 'won / lost')),
            ],
          ),
          _perfRow(PhosphorIconsRegular.trophy, const Color(0xFF890DB6), AppColors.tintPurple, 'Deals won', '${m.perfWon}', noWon, true),
          _perfRow(PhosphorIconsRegular.currencyInr, AppColors.success, AppColors.tintGreen, 'Deal value won', m.perfWonVal, noWon, true),
          _perfRow(PhosphorIconsRegular.percent, AppColors.blueBright, AppColors.tintBlue, 'Conversion rate', m.perfConv, noDec, false),
        ],
      ),
    );
  }

  /// Range picker for the Performance & records card. Each option is a `period`
  /// the member-performance endpoint accepts, so picking one re-queries.
  Future<void> _openRangeSheet() async {
    final current = ref.read(memberPerfPeriodProvider);
    await showClozrSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: 'Range'),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 26.h),
              child: Column(
                children: [
                  for (final (value, label) in kMemberPerfPeriods)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        ref.read(memberPerfPeriodProvider.notifier).state = value;
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 14.h),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppColors.bgLight)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(label,
                                  style: AppText.custom(
                                      size: 15, weight: FontWeight.w600, color: AppColors.textBody)),
                            ),
                            if (current == value)
                              Icon(PhosphorIconsBold.check, size: 17.sp, color: AppColors.success),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The range chip. It used to toast "Range — All time" and change nothing;
  /// the whole `period` path down to the query already existed, unused.
  Widget _rangeControl() {
    final period = ref.watch(memberPerfPeriodProvider);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openRangeSheet,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        decoration: BoxDecoration(
          color: AppColors.bgScreen,
          borderRadius: BorderRadius.circular(9.r),
          border: Border.all(color: AppColors.borderCard),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(memberPerfPeriodLabel(period),
                style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textBody)),
            SizedBox(width: 8.w),
            Icon(PhosphorIconsBold.caretDown, size: 11.sp, color: const Color(0xFF6C6C6C)),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String value, String label, String sub) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 12.h),
      decoration: BoxDecoration(color: const Color(0xFFF6F8FB), borderRadius: BorderRadius.circular(12.r)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary)),
              SizedBox(width: 6.w),
              Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
            ],
          ),
          SizedBox(height: 2.h),
          Text(sub, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
        ],
      ),
    );
  }

  Widget _perfRow(IconData icon, Color iconColor, Color iconBg, String label, String value, String cap, bool border) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      margin: EdgeInsets.only(top: 6.h),
      decoration: border
          ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5))))
          : null,
      child: Row(
        children: [
          Container(
            width: 34.w,
            height: 34.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10.r)),
            child: Icon(icon, size: 16.sp, color: iconColor),
          ),
          SizedBox(width: 11.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                SizedBox(height: 1.h),
                Text(value, style: AppText.custom(size: 16, weight: FontWeight.w800, color: AppColors.textPrimary)),
              ],
            ),
          ),
          if (cap.isNotEmpty)
            Text(cap, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
        ],
      ),
    );
  }

  // ── Activity log ──
  /// The real feed where the API gives one, the derived rows otherwise.
  ///
  /// The derived set is a fallback only — mock mode, or a role without
  /// `view_user_management`, which 403s. It used to be *all* this card showed:
  /// a hardcoded "Today · 09:14" sign-in, a role change attributed to the seed
  /// name "Manoj Varma", and a fixed joining date, none of it fetched.
  List<_Activity> _events(Member m, List<MemberActivity> feed) {
    if (feed.isNotEmpty) return [for (final e in feed) _fromApi(e)];
    return [
      if (m.status == 'invited')
        _Activity(PhosphorIconsRegular.paperPlaneTilt, AppColors.warningDeep, AppColors.tintAmber, 'Invite sent', '${m.email} · awaiting acceptance')
      else
        _Activity(PhosphorIconsRegular.signIn, AppColors.blueBright, AppColors.tintBlue, 'Signed in', m.name),
      _Activity(PhosphorIconsRegular.shieldCheck, AppColors.pending, AppColors.tintPurple, 'Role set to ${m.role}', ''),
      _Activity(PhosphorIconsRegular.userPlus, AppColors.success, AppColors.tintGreen, 'Joined the workspace', m.name),
    ];
  }

  /// One API row as a timeline entry, iconed by its `type` (§4.3).
  _Activity _fromApi(MemberActivity e) {
    final (icon, tone, bg) = switch (e.type) {
      'joined' => (PhosphorIconsRegular.userPlus, AppColors.success, AppColors.tintGreen),
      'login' => (PhosphorIconsRegular.signIn, AppColors.blueBright, AppColors.tintBlue),
      'role_assign' => (PhosphorIconsRegular.shieldCheck, AppColors.pending, AppColors.tintPurple),
      _ => (PhosphorIconsRegular.pencilSimple, AppColors.textLabelAlt, AppColors.bgLight),
    };
    final when = e.at == null ? '' : relativeTime(e.at);
    final sub = [e.actor, when].where((s) => s.isNotEmpty).join(' · ');
    return _Activity(icon, tone, bg, e.label, sub);
  }

  Widget _activityCard(Member m) {
    final feed = ref.watch(memberActivityProvider(m.id)).valueOrNull ?? const [];
    final events = _events(m, feed);
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.clockCounterClockwise, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Activity log', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 12.h),
          for (int i = 0; i < events.length; i++) _activityRow(events[i], i < events.length - 1),
        ],
      ),
    );
  }

  Widget _activityRow(_Activity a, bool hasLine) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: a.bg, shape: BoxShape.circle),
                child: Icon(a.icon, size: 16.sp, color: a.tone),
              ),
              if (hasLine)
                Expanded(
                  child: Container(width: 1.5.w, constraints: BoxConstraints(minHeight: 12.h), color: AppColors.borderCardSoft),
                ),
            ],
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, 6.h, 0, 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(a.sub, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthData {
  const _MonthData(this.label, this.weeks);
  final String label;
  final List<List<Color?>> weeks;
}

class _Activity {
  const _Activity(this.icon, this.tone, this.bg, this.title, this.sub);
  final IconData icon;
  final Color tone;
  final Color bg;
  final String title;
  final String sub;
}
