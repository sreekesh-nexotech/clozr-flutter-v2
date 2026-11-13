import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/mandatory_course_block.dart';
import '../../../auth/application/providers/auth_providers.dart';

/// The app-wide mandatory-course block (webapp `mandatoryBlock.store.ts`).
class MandatoryBlockState {
  const MandatoryBlockState({
    this.blocked = false,
    this.courses = const [],
    this.suppressedUntil,
  });

  /// On once a mandatory-course 403 has been seen — an empty course list
  /// still blocks.
  final bool blocked;
  final List<IncompleteCourse> courses;

  /// New blocks are ignored until then (after a recheck / a finished course).
  final DateTime? suppressedUntil;
}

/// Raised from the network layer (the shell forwards every mandatory-course
/// 403 here) and consumed by the shell's gate.
///
/// The server caches its decision for ~5 minutes, so a 403 can still arrive
/// shortly after the learner finishes the last required course. After
/// [clearBlock] re-blocking is suppressed for a short cooldown so that stale
/// 403 cannot bounce them straight back.
class MandatoryBlockNotifier extends StateNotifier<MandatoryBlockState> {
  MandatoryBlockNotifier({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(const MandatoryBlockState());

  static const reblockCooldown = Duration(minutes: 2);

  final DateTime Function() _now;

  void setBlock(List<IncompleteCourse> courses) {
    final until = state.suppressedUntil;
    if (until != null && _now().isBefore(until)) return;
    state = MandatoryBlockState(blocked: true, courses: courses);
  }

  void clearBlock() {
    state = MandatoryBlockState(suppressedUntil: _now().add(reblockCooldown));
  }
}

/// Keyed on the signed-in user, so signing out (or in as someone else) starts
/// from no block.
final mandatoryBlockProvider =
    StateNotifierProvider<MandatoryBlockNotifier, MandatoryBlockState>((ref) {
  ref.watch(sessionControllerProvider.select((s) => s.user?.id));
  return MandatoryBlockNotifier();
});
