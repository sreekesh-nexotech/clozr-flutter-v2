import 'package:intl/intl.dart';

/// Global, non-style constants. API base URLs, timeouts and pagination
/// defaults live here when the infrastructure layer lands. For the
/// presentation build these are the values the UI reads.
class AppConstants {
  AppConstants._();

  /// The signed-in user in the prototype (Manoj Varma). All "my" filters and
  /// the header workspace label key off this.
  static const String currentUserId = 'me';
  static const String workspaceName = 'Kairali Interior Works';
  static const String brandName = 'Clozr';

  /// Header date shown on the CRM home — today's date, formatted the same way
  /// the dashboard header formats it ("Thu, 9 Jul"). Computed per read rather
  /// than held as a literal so it cannot go stale, and so a session that spans
  /// midnight rolls over.
  static String get headerDate => DateFormat('EEE, d MMM').format(DateTime.now());

  /// Simulated status-bar clock, matching the design canvas.
  static const String statusBarClock = '9:41';

  /// Toast auto-dismiss duration.
  static const Duration toastDuration = Duration(milliseconds: 2200);

  /// Auto-dismiss for an error toast. Longer than [toastDuration] because a
  /// server refusal is a full sentence the user has to read and act on, and
  /// there is no way to bring it back once it has gone.
  static const Duration toastErrorDuration = Duration(milliseconds: 5000);

  /// Simulated network latency for mock data sources so skeleton/loading
  /// states are visible. Set to [Duration.zero] to disable.
  static const Duration mockLatency = Duration(milliseconds: 350);
}
