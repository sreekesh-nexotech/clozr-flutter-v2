import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/config/constants.dart';

/// Whether the module drawer is open.
final drawerOpenProvider = StateProvider<bool>((ref) => false);

/// Which drawer groups are expanded. Every group starts collapsed; tapping a
/// group (or its caret) expands it for the rest of the session.
final drawerExpandedProvider =
    StateProvider<Map<String, bool>>((ref) => const {});

/// Transient toast message. Auto-clears after [AppConstants.toastDuration].
class ToastController extends StateNotifier<String?> {
  ToastController() : super(null);
  Timer? _timer;

  void show(String message) {
    _timer?.cancel();
    state = message;
    _timer = Timer(AppConstants.toastDuration, () => state = null);
  }

  void clear() {
    _timer?.cancel();
    state = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final toastProvider =
    StateNotifierProvider<ToastController, String?>((ref) => ToastController());
