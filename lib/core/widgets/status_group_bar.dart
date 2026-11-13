import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'tab_chip.dart';

/// One chip on the [StatusGroupBar]'s group row.
class StatusGroupChip {
  const StatusGroupChip(
      {required this.code, required this.label, required this.count});

  final String code;
  final String label;
  final int count;
}

/// One chip on the [StatusGroupBar]'s second row — a status inside the open
/// group.
class StatusGroupStatusChip {
  const StatusGroupStatusChip({
    required this.key,
    required this.label,
    required this.count,
    required this.active,
    this.color,
  });

  final String key;
  final String label;
  final int count;
  final bool active;
  final Color? color;
}

/// The list header's status filter (Oct 2026 redesign): `All`, then a short,
/// fixed row of status groups; picking a group opens a second row with that
/// group's own statuses, which narrow it further.
///
/// [leading] chips sit before `All` (a deep-linked "My tasks"), [trailing]
/// after the groups ("Other / no status", "Archived", "Overdue").
///
/// The picked group is scrolled into view: another screen can open the list
/// on a group at the far end of the row (CRM home's "Lost after quote"), and
/// the second row would otherwise show statuses with no visible group picked.
class StatusGroupBar extends StatefulWidget {
  const StatusGroupBar({
    super.key,
    required this.allCount,
    required this.allActive,
    required this.onAll,
    required this.groups,
    required this.activeGroup,
    required this.onGroup,
    required this.statuses,
    required this.onStatus,
    this.leading = const [],
    this.trailing = const [],
  });

  final int allCount;
  final bool allActive;
  final VoidCallback onAll;
  final List<StatusGroupChip> groups;
  final String? activeGroup;
  final ValueChanged<String> onGroup;

  /// The statuses of [activeGroup]; the second row is hidden when empty.
  final List<StatusGroupStatusChip> statuses;
  final ValueChanged<String> onStatus;
  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  State<StatusGroupBar> createState() => _StatusGroupBarState();
}

class _StatusGroupBarState extends State<StatusGroupBar> {
  final _activeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealActive();
  }

  @override
  void didUpdateWidget(StatusGroupBar old) {
    super.didUpdateWidget(old);
    if (old.activeGroup != widget.activeGroup) _revealActive();
  }

  void _revealActive() {
    if (widget.activeGroup == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 200));
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40.h,
          child: TabChipRow(
            children: [
              ...w.leading,
              TabChip(
                  label: 'All (${w.allCount})',
                  active: w.allActive,
                  onTap: w.onAll),
              for (final g in w.groups)
                TabChip(
                  key: g.code == w.activeGroup ? _activeKey : null,
                  label: '${g.label} (${g.count})',
                  active: g.code == w.activeGroup,
                  onTap: () => w.onGroup(g.code),
                ),
              ...w.trailing,
            ],
          ),
        ),
        if (w.activeGroup != null && w.statuses.isNotEmpty) ...[
          SizedBox(height: 8.h),
          SizedBox(
            height: 40.h,
            child: TabChipRow(
              children: [
                for (final s in w.statuses)
                  TabChip(
                    label: '${s.label} (${s.count})',
                    active: s.active,
                    dotColor: s.color,
                    onTap: () => w.onStatus(s.key),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
