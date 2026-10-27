import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';

/// The sentence a refused ticket write is reported with — the webapp's
/// `TicketDetailScreen` / `issueError.ts` handling.
///
/// The server's own words, without the serializer's `status_id:` prefix
/// ("status: Cannot resolve this ticket…" read as a field dump). The one guard
/// the webapp rewords is the mandatory note before On Hold.
String ticketErrorMessage(AppError e) {
  if (e.fieldErrorCodes('status_id').contains('note_required_before_hold')) {
    return 'Add a note before placing this ticket on hold';
  }
  return e.bareMessage;
}

/// Toasts [e] once, in plain words, and withdraws it from the shell's generic
/// failure toast — which would otherwise repeat the raw `field: message` form a
/// moment later.
void showTicketError(WidgetRef ref, AppError e) {
  ref.read(apiServiceProvider).handled(e);
  ref.read(toastProvider.notifier).showError(ticketErrorMessage(e));
}
