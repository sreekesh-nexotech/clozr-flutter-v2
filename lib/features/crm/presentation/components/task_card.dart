import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/mock/mock_users.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/task_columns.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/entities/view_schema.dart';
import 'schema_mobile_card.dart';

/// The Tasks list card — the webapp's **View Settings › Tasks › Mobile view**
/// card, the same [SchemaMobileCard] the Leads and Customers lists use, laid
/// out from the org's mobile layout (`/crm/tasks/schema/?view_type=mobile`).
///
/// On the webapp's card the task title is the name, the status is the pill,
/// the due date is the time-ago, `assigned_to` is the footer, and the other
/// visible columns are label/value rows.
class TaskCard extends ConsumerWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    required this.onCall,
    this.schema = ViewSchema.empty,
  });

  final CrmTask task;
  final VoidCallback onTap;
  final VoidCallback onCall;

  /// The org's configured column set for the mobile card.
  final ViewSchema schema;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The org's own lane name and colour, not the folded built-in bucket.
    final meta = crmTaskStatusMeta(task, ref.watch(taskStatusOptionsProvider));
    final custom = task.raw['custom_fields'];
    return SchemaMobileCard(
      name: task.titleClean,
      raw: task.raw,
      customFields: custom is Map ? custom.cast<String, Object?>() : const {},
      schema: schema,
      statusLabel: meta.label,
      statusColor: meta.color,
      fallbackTime: task.due,
      fallbackPeople: [if (task.assignee.isNotEmpty) MockUsers.of(task.assignee).name],
      mockCell: (c) => taskColumnText(task, c),
      onTap: onTap,
      onCall: onCall,
    );
  }
}
