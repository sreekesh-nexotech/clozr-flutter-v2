import 'package:flutter/material.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/task_columns.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/view_schema.dart';
import 'schema_mobile_card.dart';

/// The Follow-ups list card — the webapp's **View Settings › Follow-ups ›
/// Mobile view** card, the same [SchemaMobileCard] the Leads, Customers and
/// Tasks lists use, laid out from the org's follow-up mobile layout
/// (`/crm/tasks/schema/?view_type=mobile&is_followup=true`).
class FollowupCard extends StatelessWidget {
  const FollowupCard({
    super.key,
    required this.followup,
    required this.onTap,
    required this.onCall,
    this.schema = ViewSchema.empty,
    this.status,
  });

  /// The org's own status name and colour, resolved by the screen so every
  /// card in one list agrees with the tab above it.
  final StatusMeta? status;

  final Followup followup;

  /// The org's configured card columns.
  final ViewSchema schema;

  final VoidCallback onTap;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final meta = status ?? StatusMeta$.followup[followup.status] ?? StatusMeta$.followup['due']!;
    // The headline is the follow-up's own title.
    final title = followup.title.isNotEmpty ? followup.title : '${followup.kind} — ${followup.company}';
    final custom = followup.raw['custom_fields'];
    return SchemaMobileCard(
      name: title,
      raw: followup.raw,
      customFields: custom is Map ? custom.cast<String, Object?>() : const {},
      schema: schema,
      statusLabel: meta.label,
      statusColor: meta.color,
      fallbackTime: [followup.due, followup.time].where((p) => p.trim().isNotEmpty).join(' · '),
      fallbackPeople: [if (followup.owner.isNotEmpty) MockUsers.of(followup.owner).name],
      mockCell: (c) => followupColumnText(followup, c),
      onTap: onTap,
      onCall: onCall,
    );
  }
}
