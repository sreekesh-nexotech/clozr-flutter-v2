import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/network/connectivity_provider.dart';
import '../../auth/application/providers/auth_providers.dart';
import '../../shell/application/providers/shell_providers.dart';
import '../../training/application/providers/mandatory_block_provider.dart';
import '../application/tour_controller.dart';
import '../domain/tour.dart';
import 'tour_anchor.dart';
import 'tour_popup_observer.dart';

/// The product-tour layer: invitation card, the dimmed spotlight with its
/// step card, the "Continue tour" pill and the "Tour skipped · Undo" toast.
///
/// Mounted in `MaterialApp.builder` next to the toast, above every screen and
/// sheet. It owns the *when*: a calm moment to offer, finding the step's
/// target (opening its screen first), and pausing on an interruption. What a
/// tap means for progress is [TourController]'s job.
class TourLayer extends ConsumerStatefulWidget {
  const TourLayer({super.key});

  @override
  ConsumerState<TourLayer> createState() => _TourLayerState();
}

class _TourLayerState extends ConsumerState<TourLayer>
    with WidgetsBindingObserver {
  String _location = '';
  Timer? _settle;
  Timer? _track;
  int _gen = 0;

  /// The resolved spotlight for the current step: null while looking for the
  /// target (nothing drawn), [Rect.zero] for a centred card.
  Rect? _hole;
  bool _ready = false;
  bool _navigating = false;
  String? _shownStepKey;

  static const _settleDelay = Duration(milliseconds: 1200);
  static const _targetTimeout = Duration(seconds: 4);

  TourController get _c => ref.read(tourControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appRouter.routerDelegate.addListener(_onRoute);
    TourPopupTracker.instance.open.addListener(_onInterruption);
    TourAnchorRegistry.instance.lastTap.addListener(_onAnchorTap);
    _location = _currentLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouter.routerDelegate.removeListener(_onRoute);
    TourPopupTracker.instance.open.removeListener(_onInterruption);
    TourAnchorRegistry.instance.lastTap.removeListener(_onAnchorTap);
    _settle?.cancel();
    _track?.cancel();
    super.dispose();
  }

  String _currentLocation() {
    try {
      return appRouter.routerDelegate.currentConfiguration.uri.path;
    } on Object {
      return '';
    }
  }

  // ── signals ──

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      _c.flush();
      if (s == AppLifecycleState.paused) _c.pause();
    }
  }

  void _onRoute() {
    final loc = _currentLocation();
    if (loc == _location) return;
    _location = loc;
    final st = ref.read(tourControllerProvider);
    if (st.phase == TourPhase.running && !_navigating) {
      final step = st.step;
      if (step != null && !routeMatches(step.route, loc)) {
        if (step.advance == TourAdvance.routeChange) {
          _c.next();
        } else {
          _c.pause();
        }
      }
    }
    _armOffer();
  }

  void _onInterruption() {
    if (TourPopupTracker.instance.open.value > 0) _c.pause();
    _armOffer();
  }

  void _onAnchorTap() {
    final tap = TourAnchorRegistry.instance.lastTap.value ?? '';
    final st = ref.read(tourControllerProvider);
    final step = st.step;
    if (st.phase != TourPhase.running || step == null || !_ready) return;
    if (step.advance == TourAdvance.clickTarget &&
        tap.startsWith('${step.target}#')) {
      _c.next();
    }
  }

  // ── offering ──

  void _armOffer() {
    _settle?.cancel();
    _settle = Timer(_settleDelay, _maybeOffer);
  }

  bool _calm() {
    final st = ref.read(tourControllerProvider);
    if (!st.loaded || st.phase != TourPhase.idle || st.undoTourKey != null) {
      return false;
    }
    if (!ref.read(sessionControllerProvider).isAuthenticated) return false;
    final path = _currentLocation();
    if (path.isEmpty || !Routes.metaFor(path).showNav) return false;
    if (TourPopupTracker.instance.open.value > 0) return false;
    if (ref.read(drawerOpenProvider)) return false;
    if (ref.read(isOnlineProvider).valueOrNull == false) return false;
    if (ref.read(mandatoryBlockProvider).blocked) return false;
    if (!mounted || MediaQuery.viewInsetsOf(context).bottom > 0) return false;
    return true;
  }

  void _maybeOffer() {
    if (!mounted || !_calm()) return;
    final st = ref.read(tourControllerProvider);
    if (st.offeredThisSession) return;
    final t = _c.suggestion();
    if (t != null) _c.invite(t);
  }

  // ── running a step ──

  Future<void> _runStep(TourState st) async {
    final gen = ++_gen;
    final step = st.step;
    if (step == null) return;
    setState(() {
      _ready = false;
      _hole = null;
      _shownStepKey = step.key;
    });
    _track?.cancel();

    if (!routeMatches(step.route, _currentLocation())) {
      _navigating = true;
      appRouter.go(step.route);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      _navigating = false;
      _location = _currentLocation();
      if (!mounted || gen != _gen) return;
    }

    if (step.isCentered) {
      setState(() {
        _hole = Rect.zero;
        _ready = true;
      });
      return;
    }

    final deadline = DateTime.now().add(_targetTimeout);
    BuildContext? target;
    while (DateTime.now().isBefore(deadline)) {
      target = TourAnchorRegistry.instance.contextOf(step.target);
      if (target != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || gen != _gen) return;
    }
    if (target == null || !target.mounted) {
      // Not on this user's screen (no access, feature off, empty state):
      // count it done and go on — never strand the user.
      _c.skipMissingStep();
      return;
    }
    try {
      await Scrollable.ensureVisible(target,
          alignment: 0.4, duration: const Duration(milliseconds: 250));
    } on Object {/* not in a scroll view */}
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || gen != _gen) return;
    setState(() {
      _hole = TourAnchorRegistry.instance.rectOf(step.target);
      _ready = _hole != null;
    });
    if (!_ready) {
      _c.skipMissingStep();
      return;
    }
    // Follow the target if the layout moves (list loading in, a scroll).
    _track = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || gen != _gen) return;
      final r = TourAnchorRegistry.instance.rectOf(step.target);
      if (r != null && r != _hole) setState(() => _hole = r);
    });
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    if (!onboardingToursEnabled) return const SizedBox.shrink();
    ref.listen<TourState>(tourControllerProvider, (prev, next) {
      final stepChanged = next.step?.key != _shownStepKey ||
          next.tourKey != prev?.tourKey ||
          (prev?.phase != TourPhase.running);
      if (next.phase == TourPhase.running && stepChanged) {
        _runStep(next);
      } else if (next.phase != TourPhase.running) {
        _gen++;
        _track?.cancel();
        if (_shownStepKey != null) {
          setState(() {
            _shownStepKey = null;
            _hole = null;
            _ready = false;
          });
        }
      }
      if (prev?.loaded != true && next.loaded) _armOffer();
    });
    ref.listen<bool>(drawerOpenProvider, (_, open) {
      if (open) _c.pause();
    });

    final st = ref.watch(tourControllerProvider);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboard && st.phase == TourPhase.running) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _c.pause());
    }

    final children = <Widget>[];
    switch (st.phase) {
      case TourPhase.invited:
        final t = st.tour;
        if (t != null) children.add(_invitation(t));
      case TourPhase.running:
        if (_ready && _hole != null && st.step != null) {
          children.add(_spotlight(st, st.step!, _hole!));
        }
      case TourPhase.paused:
        if (!keyboard) children.add(_resumePill(st));
      case TourPhase.idle:
        break;
    }
    if (st.undoTourKey != null) children.add(_undoToast());
    if (children.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(children: children),
      ),
    );
  }

  double get _navGap => 106.h + MediaQuery.viewPaddingOf(context).bottom;

  // Invitation (webapp InvitationCard).
  Widget _invitation(Tour t) {
    return Positioned(
      left: 16.w,
      right: 16.w,
      bottom: _navGap,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Product tour invitation',
        child: _cardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36.w,
                    height: 36.w,
                    decoration: BoxDecoration(
                        color: AppColors.navy.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10.r)),
                    child: Icon(PhosphorIconsRegular.compass,
                        size: 20.sp, color: AppColors.navy),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Take a quick tour?',
                            style: AppText.custom(
                                size: 15, weight: FontWeight.w700)),
                        SizedBox(height: 3.h),
                        Text(
                            t.description.isNotEmpty
                                ? '${t.title} — ${t.description}'
                                : t.title,
                            style: AppText.body()),
                      ],
                    ),
                  ),
                  _iconBtn(PhosphorIconsRegular.x, 'Don’t show again',
                      _c.dismissInvite),
                ],
              ),
              SizedBox(height: 14.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _textBtn('Maybe later', _c.later),
                  SizedBox(width: 8.w),
                  _primaryBtn('Start tour', () {
                    HapticFeedback.selectionClick();
                    _c.start(t.key);
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Dim + cut-out + step card (webapp Spotlight + Popover).
  Widget _spotlight(TourState st, TourStep step, Rect target) {
    final size = MediaQuery.sizeOf(context);
    final centred = target == Rect.zero;
    final hole = centred ? null : target.inflate(6);
    final passThrough = step.advance == TourAdvance.clickTarget;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final dim = Colors.black.withOpacity(0.55);

    final layers = <Widget>[
      // The dim, drawn with a rounded hole.
      Positioned.fill(
        child: IgnorePointer(
          child: TweenAnimationBuilder<Rect?>(
            tween: RectTween(end: hole ?? Rect.zero),
            duration:
                reduce ? Duration.zero : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (_, r, __) => CustomPaint(
                painter:
                    _DimPainter(hole: (hole == null) ? null : r, color: dim)),
          ),
        ),
      ),
    ];

    // Taps on the dim are swallowed (the screen beneath is not live during a
    // step). The hole itself only lets taps through for a "tap the target"
    // step; otherwise it is blocked too.
    if (hole == null) {
      layers.add(Positioned.fill(child: _absorb()));
    } else {
      layers.addAll([
        Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: math.max(0, hole.top),
            child: _absorb()),
        Positioned(
            left: 0, right: 0, top: hole.bottom, bottom: 0, child: _absorb()),
        Positioned(
            left: 0,
            width: math.max(0, hole.left),
            top: hole.top,
            height: hole.height,
            child: _absorb()),
        Positioned(
            left: hole.right,
            right: 0,
            top: hole.top,
            height: hole.height,
            child: _absorb()),
        if (!passThrough) Positioned.fromRect(rect: hole, child: _absorb()),
      ]);
    }

    final card = _stepCard(st, step);
    if (hole == null) {
      layers.add(Center(
          child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w), child: card)));
    } else {
      final spaceBelow = size.height - hole.bottom;
      final below = switch (step.placement) {
        TourPlacement.bottom => true,
        TourPlacement.top => false,
        _ => spaceBelow > hole.top,
      };
      layers.add(Positioned(
        left: 16.w,
        right: 16.w,
        top: below ? hole.bottom + 12.h : null,
        bottom: below ? null : size.height - hole.top + 12.h,
        child: card,
      ));
    }
    return Positioned.fill(child: Stack(children: layers));
  }

  Widget _absorb() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: const SizedBox.expand(),
      );

  Widget _stepCard(TourState st, TourStep step) {
    final (at, of) = st.counter;
    final last = st.index >= (st.tour?.mobileSteps.length ?? 1) - 1;
    final hint = switch (step.advance) {
      TourAdvance.clickTarget => 'Tap the highlighted item to continue.',
      TourAdvance.routeChange => 'Open the next page to continue.',
      TourAdvance.next => null,
    };
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Tour step $at of $of',
      child: _cardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('$at of $of',
                    style: AppText.custom(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.textMuted,
                        letterSpacing: 0.4)),
                const Spacer(),
                _iconBtn(PhosphorIconsRegular.x, 'Skip tour', _c.skipTour),
              ],
            ),
            SizedBox(height: 2.h),
            Text(step.title,
                style: AppText.custom(size: 16, weight: FontWeight.w700)),
            if (step.body.isNotEmpty) ...[
              SizedBox(height: 5.h),
              Text(step.body, style: AppText.body()),
            ],
            if (hint != null) ...[
              SizedBox(height: 8.h),
              Text(hint,
                  style: AppText.custom(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.blueBright)),
            ],
            SizedBox(height: 14.h),
            Row(
              children: [
                _textBtn('Skip tour', _c.skipTour),
                const Spacer(),
                if (st.index > 0) ...[
                  _textBtn('Back', _c.back),
                  SizedBox(width: 6.w),
                ],
                if (step.advance == TourAdvance.next)
                  _primaryBtn(last ? 'Done' : 'Next', () {
                    HapticFeedback.selectionClick();
                    _c.next();
                  }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // "Continue tour (2 of 4)" (webapp ResumePill).
  Widget _resumePill(TourState st) {
    final (at, of) = st.counter;
    return Positioned(
      right: 16.w,
      bottom: _navGap,
      child: Container(
        padding: EdgeInsets.fromLTRB(14.w, 6.h, 6.w, 6.h),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(22.r),
          boxShadow: [
            BoxShadow(
                color: AppColors.navy.withOpacity(0.3),
                blurRadius: 14,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.compass,
                size: 16.sp, color: AppColors.white),
            SizedBox(width: 6.w),
            Text('Continue tour ($at of $of)',
                style: AppText.custom(
                    size: 13, weight: FontWeight.w600, color: AppColors.white)),
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: () {
                if (TourPopupTracker.instance.open.value > 0) return;
                ref.read(drawerOpenProvider.notifier).state = false;
                FocusManager.instance.primaryFocus?.unfocus();
                _c.resume();
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16.r)),
                child: Text('Resume',
                    style: AppText.custom(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.navy)),
              ),
            ),
            Semantics(
              button: true,
              label: 'Skip tour',
              child: GestureDetector(
                onTap: _c.skipTour,
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: Icon(PhosphorIconsRegular.x,
                      size: 14.sp, color: AppColors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // "Tour skipped · Undo" (webapp SkipToast).
  Widget _undoToast() {
    return Positioned(
      left: 16.w,
      right: 16.w,
      bottom: _navGap,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.w, 10.h, 8.w, 10.h),
        decoration: BoxDecoration(
            color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                  'Tour skipped. Replay it any time from the menu › Product tours.',
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w500,
                      color: AppColors.white)),
            ),
            GestureDetector(
              onTap: _c.undoSkip,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                child: Text('Undo',
                    style: AppText.custom(
                        size: 13,
                        weight: FontWeight.w700,
                        color: const Color(0xFF8AB4FF))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── bits ──

  Widget _cardBox({required Widget child}) => Container(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 12.w, 12.h),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 24,
                offset: const Offset(0, 10)),
          ],
        ),
        child: child,
      );

  Widget _primaryBtn(String label, VoidCallback onTap) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: 40.h, minWidth: 72.w),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(10.r)),
            child: Text(label,
                style: AppText.custom(
                    size: 14, weight: FontWeight.w700, color: AppColors.white)),
          ),
        ),
      );

  Widget _textBtn(String label, VoidCallback onTap) => Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: 40.h),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: 10.w),
            child: Text(label,
                style: AppText.custom(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
        ),
      );

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(6.w),
            child: Icon(icon, size: 18.sp, color: AppColors.textMuted),
          ),
        ),
      );
}

class _DimPainter extends CustomPainter {
  _DimPainter({required this.hole, required this.color});
  final Rect? hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null || h.isEmpty) {
      canvas.drawPath(full, Paint()..color = color);
      return;
    }
    final cut = Path()
      ..addRRect(RRect.fromRectAndRadius(h, const Radius.circular(12)));
    canvas.drawPath(Path.combine(PathOperation.difference, full, cut),
        Paint()..color = color);
    canvas.drawRRect(
        RRect.fromRectAndRadius(h, const Radius.circular(12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withOpacity(0.9));
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole || old.color != color;
}
