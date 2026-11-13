import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sign-in backdrop: a pale blue→green wash with a frosted "orbit" sphere
/// rising from the bottom edge and CRM feature icons drifting around it —
/// the mobile take on the portal login's orbit graphic.
///
/// Purely decorative: ignores pointers, is excluded from semantics, stops
/// moving when the system asks for reduced motion, and fades out while the
/// keyboard is up so it never competes with typing.
class LoginBackdrop extends StatefulWidget {
  const LoginBackdrop({super.key});

  @override
  State<LoginBackdrop> createState() => _LoginBackdropState();
}

class _LoginBackdropState extends State<LoginBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 70));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  // Outer ring (slower, clockwise) and inner ring (counter-clockwise).
  static const _outer = <_Chip>[
    _Chip(Icons.filter_alt_outlined, Color(0xFF3E8EDE), 0.00),
    _Chip(Icons.mail_outline_rounded, Color(0xFFE5484D), 0.125),
    _Chip(Icons.call_outlined, Color(0xFFF08A24), 0.25),
    _Chip(Icons.attach_file_rounded, Color(0xFF8A94A6), 0.375),
    _Chip(Icons.event_note_outlined, Color(0xFFD6409F), 0.50),
    _Chip(Icons.bolt_rounded, Color(0xFFE2A100), 0.625),
    _Chip(Icons.mail_outline_rounded, Color(0xFF3E8EDE), 0.75),
    _Chip(Icons.call_outlined, Color(0xFF6BB23B), 0.875),
  ];
  static const _inner = <_Chip>[
    _Chip(Icons.track_changes_rounded, Color(0xFF3E8EDE), 0.05),
    _Chip(Icons.auto_awesome_outlined, Color(0xFF6BB23B), 0.30),
    _Chip(Icons.track_changes_rounded, Color(0xFF8C7BE8), 0.55),
    _Chip(Icons.bolt_rounded, Color(0xFFE2A100), 0.80),
  ];

  @override
  Widget build(BuildContext context) {
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEEF2F9), Color(0xFFF4F6FA), Color(0xFFE9F7EE)],
              stops: [0, 0.55, 1],
            ),
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: keyboardUp ? 0 : 1,
            child: TickerMode(
              enabled: !keyboardUp,
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final h = c.maxHeight;
                  // Sphere centred on the bottom edge: only its top half shows.
                  final centre = Offset(w / 2, h + w * 0.06);
                  final rOuter = w * 0.5;
                  final rInner = w * 0.3;
                  return AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) {
                      final t = _spin.value * 2 * math.pi;
                      return Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _SpherePainter(centre, w),
                            ),
                          ),
                          for (final chip in _outer)
                            _place(chip, centre, rOuter, t),
                          for (final chip in _inner)
                            _place(chip, centre, rInner, -t * 1.4),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _place(_Chip chip, Offset centre, double radius, double spin) {
    // Angles run over the full circle; those below the screen edge are
    // simply off-canvas, so chips appear from one side and leave the other.
    final a = chip.phase * 2 * math.pi + spin;
    const size = 38.0;
    return Positioned(
      left: centre.dx + radius * math.cos(a) - size / 2,
      top: centre.dy + radius * math.sin(a) - size / 2,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.92),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00113B).withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(chip.icon, size: 18, color: chip.color),
      ),
    );
  }
}

class _Chip {
  const _Chip(this.icon, this.color, this.phase);
  final IconData icon;
  final Color color;

  /// Starting position on the ring, as a fraction of a full turn.
  final double phase;
}

/// Concentric translucent discs with a soft green core — the frosted sphere.
class _SpherePainter extends CustomPainter {
  const _SpherePainter(this.centre, this.width);
  final Offset centre;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft radial discs (opaque centre fading outward) read as frosted glass
    // rather than hard-edged circles.
    void disc(double r, Color inner, Color outer) {
      final rect = Rect.fromCircle(center: centre, radius: r);
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [inner, outer],
            stops: const [0.55, 1],
          ).createShader(rect),
      );
    }

    disc(width * 0.78, Colors.white.withOpacity(0.0),
        const Color(0xFFD6E4F5).withOpacity(0.0));
    disc(width * 0.64, const Color(0xFFE3EDF8).withOpacity(0.7),
        const Color(0xFFCFE0F3).withOpacity(0.55));
    disc(width * 0.50, const Color(0xFFF5FAFF).withOpacity(0.85),
        const Color(0xFFD7EFE0).withOpacity(0.8));
    disc(width * 0.36, const Color(0xFFE9F8EC).withOpacity(0.9),
        const Color(0xFFCDEBD2).withOpacity(0.85));
    disc(width * 0.20, Colors.white.withOpacity(0.9),
        Colors.white.withOpacity(0.6));
  }

  @override
  bool shouldRepaint(_SpherePainter old) =>
      old.centre != centre || old.width != width;
}
