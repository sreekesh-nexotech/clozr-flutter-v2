import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'ticket_form_screen.dart';

/// Edit Ticket (`?id=<issue_id>`) — the shared [TicketFormScreen] in edit
/// mode, seeded from the ticket.
class EditTicketScreen extends StatelessWidget {
  const EditTicketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    return TicketFormScreen(key: ValueKey(id), editId: id);
  }
}
