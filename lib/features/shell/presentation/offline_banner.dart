import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/network/connectivity_provider.dart';

/// Persistent strip across the very top of the app reporting the device's own
/// connectivity, mounted once in `MaterialApp.builder` (see [ClozrApp]) so it
/// is visible over the login/splash screens too, not only the signed-in shell.
///
/// This is what makes going offline show up immediately instead of waiting on
/// whatever screen happens to be open to attempt and fail a request: it reacts
/// to [isOnlineProvider] directly, so the banner appears the instant wifi/data
/// is switched off. A cached screen can then go on quietly showing its stale
/// data underneath — that is the right call, not a bug — but the banner is
/// what tells the user it *is* stale rather than leaving them to guess.
///
/// Two states render, everything else is silence: red "No internet
/// connection" for as long as the device is offline, and a green "Back
/// online" for a couple of seconds when it reconnects — a silent disappearance
/// reads as "did that fix it or did the app just give up telling me", so
/// reconnecting gets its own confirmation instead.
class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key});

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  Timer? _backOnlineTimer;
  bool _showBackOnline = false;

  // Whether this device has been seen offline at all yet — an app that has
  // been online since launch has nothing to "come back" from, so it must
  // never flash "Back online" on its very first connectivity reading.
  bool _wasEverOffline = false;

  @override
  void dispose() {
    _backOnlineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(isOnlineProvider, (previous, next) {
      final wasOnline = previous?.valueOrNull;
      final isOnline = next.valueOrNull;
      if (isOnline == null) return;
      if (!isOnline) {
        _wasEverOffline = true;
        _backOnlineTimer?.cancel();
        if (_showBackOnline) setState(() => _showBackOnline = false);
        return;
      }
      // Reconnected: only celebrate a *transition* out of offline, not the
      // steady-state "still online" ticks the stream can also emit.
      if (_wasEverOffline && wasOnline == false) {
        _backOnlineTimer?.cancel();
        setState(() => _showBackOnline = true);
        _backOnlineTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showBackOnline = false);
        });
      }
    });

    final isOnline = ref.watch(isOnlineProvider).valueOrNull;
    final offline = isOnline == false;
    final visible = offline || _showBackOnline;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: !visible
            ? const SizedBox(width: double.infinity)
            : SafeArea(
                bottom: false,
                child: Material(
                  // A soft tint rather than a solid alarm-red block — the same
                  // "light background, saturated accent" pairing the offline
                  // [ErrorState] icon already uses, so this reads as a status
                  // strip rather than a full-bleed error.
                  color: offline ? AppColors.tintRed : AppColors.tintGreen,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: (offline ? AppColors.error : AppColors.success)
                              .withOpacity(0.18),
                        ),
                      ),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 7.h),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          offline
                              ? PhosphorIconsFill.wifiSlash
                              : PhosphorIconsFill.wifiHigh,
                          size: 14.sp,
                          color: offline ? AppColors.error : AppColors.success,
                        ),
                        SizedBox(width: 7.w),
                        Text(
                          offline ? 'No internet connection' : 'Back online',
                          style: AppText.custom(
                              size: 12,
                              weight: FontWeight.w700,
                              color: offline ? AppColors.error : AppColors.success),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
