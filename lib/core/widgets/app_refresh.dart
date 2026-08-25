import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../app/theme/app_colors.dart';

/// The app's pull-to-refresh chrome, wrapped around a scrollable.
///
/// Two things to know when using it:
///
/// * The [child] must be a scrollable with [AlwaysScrollableScrollPhysics].
///   [RefreshIndicator] drives itself off scroll notifications, and a list whose
///   content fits the viewport emits none under the default physics — so a short
///   list, or an empty state, simply would not respond to the gesture.
/// * [onRefresh]'s future is what the spinner's lifetime is tied to. Return
///   before the refetch lands and the spinner disappears while stale rows are
///   still on screen; let it throw and the spinner sticks. [settle] handles
///   both.
class AppRefresh extends StatelessWidget {
  const AppRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// How far down the spinner settles. Defaults to a value that clears the
  /// list-screen header; pass a larger one under a taller sticky header.
  final double? displacement;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: displacement ?? 28.h,
      strokeWidth: 2.4,
      color: AppColors.navy,
      backgroundColor: AppColors.white,
      child: child,
    );
  }
}

/// Awaits every future in [futures], swallowing failures.
///
/// A refresh reports its own outcome: the providers being refetched are the same
/// ones the screen renders, so a failure already surfaces as that screen's error
/// state or a stale-data banner. Letting the error escape here would instead
/// leave [RefreshIndicator] with a rejected future — the spinner stops, but the
/// exception lands in the framework's error handler and gets reported as a crash
/// for something the UI has already handled.
///
/// Note this waits for *all* of them rather than stopping at the first failure,
/// which `Future.wait` would do — one dead endpoint must not cancel the refresh
/// of the others.
Future<void> settle(Iterable<Future<Object?>> futures) async {
  await Future.wait([
    for (final f in futures) f.then<void>((_) {}, onError: (_, __) {}),
  ]);
}
