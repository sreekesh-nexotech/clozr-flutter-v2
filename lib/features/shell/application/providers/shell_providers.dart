import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/config/constants.dart';

/// Whether the module drawer is open.
final drawerOpenProvider = StateProvider<bool>((ref) => false);

/// Which drawer groups are expanded. Every group starts collapsed; tapping a
/// group (or its caret) expands it for the rest of the session.
final drawerExpandedProvider =
    StateProvider<Map<String, bool>>((ref) => const {});

/// One toast: the text, and whether it reports a failure.
///
/// The distinction is not cosmetic. Every toast used to render with the green
/// success check, so a refusal the backend sent back — "Task updates are not
/// allowed on weekends." — appeared under a tick, which reads as *done*.
class ToastMessage {
  const ToastMessage(this.text, {this.isError = false});

  final String text;
  final bool isError;
}

/// Transient toast message. Auto-clears after [AppConstants.toastDuration]
/// (errors get [AppConstants.toastErrorDuration] — a refusal is a sentence to
/// read, not a word to glance at).
class ToastController extends StateNotifier<ToastMessage?> {
  ToastController() : super(null);
  Timer? _timer;

  void show(String message) => _show(ToastMessage(message), AppConstants.toastDuration);

  /// A failure the user has to read: server refusals, validation, write errors.
  void showError(String message) =>
      _show(ToastMessage(message, isError: true), AppConstants.toastErrorDuration);

  void _show(ToastMessage message, Duration duration) {
    _timer?.cancel();
    state = message;
    _timer = Timer(duration, () => state = null);
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

final toastProvider = StateNotifierProvider<ToastController, ToastMessage?>(
    (ref) => ToastController());

/// The backend message a screen has already put on the page as its whole
/// body (a permission refusal rendered as the screen's state), so the shell's
/// catch-all failure toast has nothing to add. Cleared on every navigation;
/// set by screens via [reportFailureOnPage].
final pageReportedFailureProvider = StateProvider<String?>((ref) => null);

/// Screens call this from the build that renders [message] in full. Deferred
/// so provider state is never mutated during a build.
void reportFailureOnPage(WidgetRef ref, String message) {
  Future<void>.microtask(() {
    if (!ref.context.mounted) return;
    ref.read(pageReportedFailureProvider.notifier).state = message;
  });
}
