import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/app_card.dart';

// The webapp's SLA section on a record (`SlaClocksSection` + `SlaChip`):
// one chip per running/paused/met/breached clock, hidden when there are none.

enum SlaChipState { running, atRisk, breached, met, paused }

class SlaClockChip {
  const SlaClockChip({required this.state, required this.text});

  final SlaChipState state;
  final String text;

  /// Webapp `toSlaClock` + `slaChip`; null for a clock with no chip
  /// (cancelled, or a target/state the app does not know).
  static SlaClockChip? fromJson(Map<String, dynamic> j, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final layer = switch (j['layer']) {
      'commitment' => 'Client',
      'performance' => 'Team',
      _ => null,
    };
    final target = switch (j['target']) {
      'first_response' => 'First response',
      'resolution' => 'Resolution',
      'first_touch' => 'First touch',
      'idle' => 'Idle',
      'completion' => 'Completion',
      _ => null,
    };
    final wire = '${j['state'] ?? ''}';
    if (layer == null || target == null) return null;
    if (!const {'running', 'paused', 'met', 'breached'}.contains(wire)) return null;
    final remaining = (j['remaining_seconds'] as num?)?.toInt();
    DateTime? time(String k) => DateTime.tryParse('${j[k] ?? ''}');
    final warningAt = time('warning_at');

    var state = switch (wire) {
      'paused' => SlaChipState.paused,
      'met' => SlaChipState.met,
      'breached' => SlaChipState.breached,
      _ => SlaChipState.running,
    };
    if (state == SlaChipState.running) {
      if (remaining != null && remaining < 0) {
        state = SlaChipState.breached;
      } else if (j['warned_at'] != null || (warningAt != null && !warningAt.isAfter(at))) {
        state = SlaChipState.atRisk;
      }
    }

    final String status;
    switch (state) {
      case SlaChipState.running:
      case SlaChipState.atRisk:
        status = remaining == null ? 'Running' : '${duration(remaining)} left';
      case SlaChipState.breached:
        status = remaining != null && remaining < 0 ? 'Overdue ${duration(-remaining)}' : 'Breached';
      case SlaChipState.met:
        final started = time('started_at');
        final met = time('met_at');
        final paused = (j['paused_seconds'] as num?)?.toInt() ?? 0;
        status = started != null && met != null
            ? 'Met in ${duration(met.difference(started).inSeconds - paused)}'
            : 'Met';
      case SlaChipState.paused:
        status = remaining == null ? 'Paused' : 'Paused · ${duration(remaining)} left';
    }
    return SlaClockChip(state: state, text: '$layer · $target — $status');
  }

  /// `3d 2h` / `2h 15m` / `45m`.
  static String duration(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

/// `GET /sla/clocks/?module=lead&id=` — re-read every minute like the webapp.
/// Any failure (404 included) reads as "no clocks".
final leadSlaClocksProvider = FutureProvider.autoDispose.family<List<SlaClockChip>, (String, String)>((ref, rec) async {
  final (module, id) = rec;
  final timer = Timer(const Duration(seconds: 60), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    final body = await ref.read(apiServiceProvider).get('/sla/clocks/', query: {'module': module, 'id': id}, quiet: true);
    final clocks = body is Map ? body['clocks'] : null;
    final out = <SlaClockChip>[];
    if (clocks is List) {
      for (final c in clocks) {
        final chip = c is Map ? SlaClockChip.fromJson(Map<String, dynamic>.from(c)) : null;
        if (chip != null) out.add(chip);
      }
    }
    return out;
  } on Object {
    return const [];
  }
});

class LeadSlaClocks extends ConsumerWidget {
  const LeadSlaClocks({super.key, required this.leadId, this.module = 'lead'});

  /// The record's id (a lead's, or a task's with [module] `task`).
  final String leadId;
  final String module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = ref.watch(leadSlaClocksProvider((module, leadId))).valueOrNull ?? const [];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: ClozrCard(
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(PhosphorIconsRegular.timer, size: 15.sp, color: AppColors.textMuted),
              SizedBox(width: 6.w),
              Text('SLA', style: AppText.captionStrong(color: AppColors.textMuted)),
            ]),
            SizedBox(height: 10.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [for (final c in chips) _chip(c)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(SlaClockChip c) {
    final (bg, fg, icon) = switch (c.state) {
      SlaChipState.running => (AppColors.tintBlue, AppColors.blueBright, PhosphorIconsRegular.clock),
      SlaChipState.atRisk => (AppColors.tintAmber, AppColors.warningDeep, PhosphorIconsRegular.warningCircle),
      SlaChipState.breached => (AppColors.tintRed, AppColors.error, PhosphorIconsRegular.warning),
      SlaChipState.met => (AppColors.tintGreen, AppColors.success, PhosphorIconsBold.check),
      SlaChipState.paused => (AppColors.bgChipGrey, AppColors.textMuted, PhosphorIconsRegular.pause),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13.sp, color: fg),
        SizedBox(width: 5.w),
        Flexible(child: Text(c.text, style: AppText.custom(size: 12, weight: FontWeight.w700, color: fg))),
      ]),
    );
  }
}
