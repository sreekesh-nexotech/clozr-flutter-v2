import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/config/constants.dart';

/// Whether the module drawer is open.
final drawerOpenProvider = StateProvider<bool>((ref) => false);

/// Which drawer groups are expanded (CRM open by default, mirroring the
/// prototype's `drawerExpanded: { crm: true }`).
final drawerExpandedProvider =
    StateProvider<Map<String, bool>>((ref) => {'crm': true});

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
