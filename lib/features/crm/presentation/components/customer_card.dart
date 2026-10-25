import 'package:flutter/material.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/customers_columns.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/view_schema.dart';
import 'schema_mobile_card.dart';

/// The Customers list card — the webapp's **View Settings › Customers ›
/// Mobile view** card, the same [SchemaMobileCard] the Leads list uses, laid
/// out from the org's `mobile` layout (`/crm/customers/schema/?view_type=mobile`).
class CustomerCard extends StatelessWidget {
  const CustomerCard({
    super.key,
    required this.customer,
    required this.onTap,
    required this.onCall,
    this.schema = ViewSchema.empty,
  });

  final Customer customer;
  final VoidCallback onTap;
  final VoidCallback onCall;

  /// The org's configured column set for the mobile card.
  final ViewSchema schema;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.customer[customer.status] ?? StatusMeta$.customer['active']!;
    final custom = customer.raw['custom_fields'];
    return SchemaMobileCard(
      name: customer.name,
      raw: customer.raw,
      customFields: custom is Map ? custom.cast<String, Object?>() : const {},
      schema: schema,
      notif: customer.notif,
      statusLabel: meta.label,
      statusColor: meta.color,
      fallbackCompany: customer.company ?? '',
      fallbackValue: customer.value,
      fallbackTime: customer.time,
      fallbackPeople: [for (final id in customer.team) MockUsers.of(id).name],
      mockCell: (c) => customerColumnText(customer, c),
      onTap: onTap,
      onCall: onCall,
    );
  }
}
