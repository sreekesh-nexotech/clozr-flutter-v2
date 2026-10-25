import 'package:flutter/material.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/leads_columns.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/lead_schema.dart';
import 'schema_mobile_card.dart';

/// The Leads list card — the webapp's **View Settings › Leads › Mobile view**
/// card ([SchemaMobileCard]), laid out from the org's `mobile` layout
/// (`/crm/leads/schema/?view_type=mobile`).
class LeadCard extends StatelessWidget {
  const LeadCard({
    super.key,
    required this.lead,
    required this.onTap,
    required this.onCall,
    this.status,
    this.schema = LeadListSchema.empty,
  });

  final Lead lead;

  /// The org's stage for this lead: its name when the row carries only an id,
  /// its colour on a Status row. The header pill is amber, as on the webapp.
  final StatusMeta? status;

  /// The org's `mobile` column set.
  final LeadListSchema schema;

  final VoidCallback onTap;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return SchemaMobileCard(
      name: lead.name,
      raw: lead.raw,
      customFields: lead.customFields,
      schema: schema,
      notif: lead.notif,
      statusLabel: status?.label ?? lead.statusName,
      statusColor: status?.color,
      fallbackCompany: lead.company ?? '',
      fallbackValue: lead.value,
      fallbackTime: lead.time,
      fallbackPeople: [for (final id in lead.team) MockUsers.of(id).name],
      mockCell: (c) => leadColumnText(lead, c),
      onTap: onTap,
      onCall: onCall,
    );
  }
}
