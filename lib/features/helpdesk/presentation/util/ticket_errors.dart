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
/// 412 STALE_RECORD: the ticket changed elsewhere since it was read (its
/// `If-Match` version no longer matches) — webapp parity C06.
bool isTicketStale(AppError e) =>
    e.statusCode == 412 || e.code == 'STALE_RECORD';

/// 409 `issue_resolved_locked`: a resolved ticket refuses edits other than
/// reopening it — webapp parity C07.
bool isTicketResolvedLocked(AppError e) =>
    e.code == 'issue_resolved_locked' ||
    (e.statusCode == 409 &&
        '${e.extra ?? ''} ${e.message}'.contains('issue_resolved_locked'));

/// The sentence for a resolved-ticket lock.
const ticketResolvedLockedMessage =
    'This ticket is resolved — reopen it before editing.';

String ticketErrorMessage(AppError e) {
  if (isTicketResolvedLocked(e)) return ticketResolvedLockedMessage;
  if (isTicketStale(e)) {
    return 'Changed elsewhere — reload to see the latest version.';
  }
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
