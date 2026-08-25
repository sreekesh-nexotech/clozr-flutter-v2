import '../domain/entities/customer.dart';
import '../domain/entities/view_schema.dart';
import 'schema_columns.dart';

/// Turning the org's configured columns into text the Customers list card can
/// show — the same contract [leadExtraColumns] gives the Leads card.
///
/// Without this the card could only ever render the six slots it was built
/// with, so a field the org put on its mobile layout — `email`, `address`,
/// `assigned_team` — arrived in the payload and was drawn by nothing.

/// Columns the card already renders in its own frame: the name, the company
/// line, the need/value pair, the status pill, the timestamp and the avatar
/// row. Excluded from the extra strip so nothing appears twice.
const Set<String> kCustomerCardFrameColumns = {
  'name',
  'organization_name',
  'value_need',
  'purpose',
  'status',
  'status_name',
  'activity',
  'last_followup_at',
  'created_at',
  'status_entered_at',
  'assignees',
};

/// The extra columns to render as chips: everything the org made visible that
/// the fixed layout does not already show, in the org's order.
///
/// A column with no value for this customer is dropped rather than rendered
/// blank — on a card an empty slot is noise, where on a detail page it would be
/// information.
List<({String label, String value})> customerExtraColumns(
  Customer customer,
  ViewSchema schema,
) =>
    schemaExtraColumns(schema, kCustomerCardFrameColumns,
        (c) => customerColumnText(customer, c));

/// The display text for one column of [customer], or null when there is nothing
/// to show.
///
/// A built-in the entity does not carry returns null rather than a placeholder,
/// so the column is simply not rendered — the same rule the Leads card uses.
String? customerColumnText(Customer customer, ViewColumn column) {
  // The entity's own fields first, because they are already formatted the way
  // the card should read them — "₹18L" rather than 1800000, a status key rather
  // than a nested object.
  final typed = switch (column.name) {
    'name' => customer.name,
    'organization_name' => customer.company,
    'email' => customer.email,
    'phone' || 'mobile' => customer.phone,
    'address' || 'location' => customer.location,
    'website' => customer.website,
    'source' => customer.source,
    'score' => customer.score == 0 ? null : '${customer.score}',
    'value_need' => customer.value,
    'purpose' => customer.project,
    'last_followup_type' => customer.lastFu,
    _ => null,
  };
  if (typed != null && typed.trim().isNotEmpty) return typed.trim();

  // Anything else straight off the row, by the column's own name. This is what
  // keeps the card open-ended: a field nobody anticipated still renders, with
  // whatever the backend returned for it.
  return rawColumnText(customer.raw, column);
}

