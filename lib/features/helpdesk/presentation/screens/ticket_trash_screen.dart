import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/tickets_providers.dart';
import '../../domain/entities/ticket.dart';

/// Tickets › Trash — webapp `TicketTrashDrawer` (parity C09).
///
/// Deleting a ticket moves it here with its notes, files and activity; Restore
/// brings it back with everything it had. Search and paging as on the web;
/// whoever can delete tickets can restore them.
class TicketTrashScreen extends ConsumerStatefulWidget {
  const TicketTrashScreen({super.key});

  @override
  ConsumerState<TicketTrashScreen> createState() => _TicketTrashScreenState();
}

class _TicketTrashScreenState extends ConsumerState<TicketTrashScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  final List<Ticket> _rows = [];
  int _page = 1;
  bool _more = false;
  bool _loading = true;
  String? _error;
  String? _restoringId;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _page = 1;
        _rows.clear();
      }
    });
    try {
      final r = await ref
          .read(ticketsRepositoryProvider)
          .getDeletedTickets(search: _search.text, page: _page);
      if (!mounted) return;
      setState(() {
        _rows.addAll(r.rows);
        _more = r.more;
        _loading = false;
      });
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (!mounted) return;
      setState(() {
        _error = e.bareMessage;
        _loading = false;
      });
    }
  }

  Future<void> _restore(Ticket t) async {
    if (!ensurePermission(ref, 'issue', PermVerb.delete)) return;
    setState(() => _restoringId = t.id);
    try {
      await ref.read(ticketsRepositoryProvider).restoreTicket(t.id);
      if (!mounted) return;
      refreshTickets(ref);
      ref.invalidate(ticketStatusCountsProvider);
      setState(() => _rows.removeWhere((r) => r.id == t.id));
      ref.read(toastProvider.notifier).show('${t.displayRef} restored');
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (mounted) ref.read(toastProvider.notifier).showError(e.bareMessage);
    } finally {
      if (mounted) setState(() => _restoringId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgDetail,
      child: Column(children: [
        const DetailAppBar(section: 'Trash'),
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
          child: TextField(
            controller: _search,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(
                  const Duration(milliseconds: 350), () => _load(reset: true));
            },
            decoration: InputDecoration(
              hintText: 'Search deleted tickets…',
              prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass,
                  size: 18.sp, color: AppColors.textMuted),
              isDense: true,
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: AppColors.borderInput)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: AppColors.borderInput)),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 6.h),
          child: Text(
              'Deleted tickets keep their notes, files and activity. '
              'Restore brings one back with everything it had.',
              style: AppText.caption()),
        ),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      return EmptyState(
        icon: PhosphorIconsRegular.warningCircle,
        title: "Couldn't load the trash",
        body: _error!,
        ctaLabel: 'Retry',
        ctaIcon: PhosphorIconsBold.arrowClockwise,
        onCta: () => _load(reset: true),
      );
    }
    if (_rows.isEmpty) {
      return EmptyState(
        icon: PhosphorIconsRegular.trash,
        title: _search.text.trim().isEmpty
            ? 'Trash is empty'
            : 'No deleted tickets match',
        body: 'Tickets you delete appear here and can be restored.',
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 40.h),
      itemCount: _rows.length + (_more ? 1 : 0),
      separatorBuilder: (_, __) => SizedBox(height: 10.h),
      itemBuilder: (context, i) {
        if (i == _rows.length) {
          return Center(
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      _page++;
                      _load(reset: false);
                    },
              child: Text(_loading ? 'Loading…' : 'Load more'),
            ),
          );
        }
        final t = _rows[i];
        final busy = _restoringId == t.id;
        return ClozrCard(
          radius: 14,
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          onTap: () => context.push('${Routes.ticketDetail}?id=${t.id}'),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.displayRef, style: AppText.caption()),
                  SizedBox(height: 2.h),
                  Text(t.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong()),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _restore(t),
              icon:
                  Icon(PhosphorIconsRegular.arrowCounterClockwise, size: 15.sp),
              label: Text(busy ? 'Restoring…' : 'Restore'),
            ),
          ]),
        );
      },
    );
  }
}
