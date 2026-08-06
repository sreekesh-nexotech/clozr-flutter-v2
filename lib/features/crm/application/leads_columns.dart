import '../../../core/utils/relative_time.dart';
import '../../../data/mock/mock_users.dart';
import '../domain/entities/lead.dart';
import '../domain/entities/lead_schema.dart';

/// Turning the org's configured columns into text the Leads list card can show.

/// Columns the card already renders in its own layout — name, the sub-title
/// lines, the status pill, value, timestamp and the avatar row. They are
/// excluded from the extra-column strip so nothing appears twice.
const Set<String> kLeadCardFrameColumns = {
  'lead_name',
  'organization_name',
  'products',
  'lead_source',
  'status',
  'lead_value',
  'activity',
  'assignees',
};

/// Columns the lead **detail** page renders in its own chrome rather than as an
/// information row: the profile card (name, company, value, status), the score
/// card, and the Owner & Assignees block. Excluded from [leadDetailRows] so a
/// field is never shown twice on one screen.
const Set<String> kLeadDetailFrameColumns = {
  'lead_name',
  'organization_name',
  'lead_value',
  'status',
  'lead_score',
  'lead_owner',
  'assignees',
  'assigned_team',
};

/// The information rows for the lead detail page: every column the org made
/// visible on its `detail` layout that the page's chrome does not already show,
/// in the org's order and under the org's labels.
///
/// Unlike the list card, layout and payload agree here — the record endpoint
/// trims itself to this same `detail` config — so a visible column having no
/// value means the lead genuinely has none. Those rows are kept and rendered
/// as `—`, because on a detail page "we have no phone number for this lead" is
/// information; a silently missing row is not.
List<({String label, String value})> leadDetailRows(
  Lead lead,
  LeadListSchema schema,
) {
  final out = <({String label, String value})>[];
  for (final column in schema.columns) {
    if (kLeadDetailFrameColumns.contains(column.name)) continue;
    final value = leadColumnText(lead, column);
    // A column the entity cannot supply at all (null) is skipped; one it can
    // supply but that is empty for this lead shows as an em dash.
    if (value == null) continue;
    out.add((label: column.label, value: value.isEmpty ? '—' : value));
  }
  return out;
}

/// The extra columns to render as chips: everything the org made visible that
/// the card's fixed layout does not already show, in the org's order.
///
/// Columns whose value is empty for this lead are dropped — including ones the
/// org put on the card but hid from the list view, whose values the payload
/// never carries (the data endpoint trims to the `list` config).
List<({String label, String value})> leadExtraColumns(
  Lead lead,
  LeadListSchema schema,
) {
  final out = <({String label, String value})>[];
  for (final column in schema.columns) {
    if (kLeadCardFrameColumns.contains(column.name)) continue;
    final value = leadColumnText(lead, column);
    if (value == null || value.isEmpty) continue;
    out.add((label: column.label, value: value));
  }
  return out;
}

/// The display text for one column of [lead], or null when there is nothing to
/// show.
///
/// Built-ins are read from the entity's own fields; custom fields from the
/// row's `custom_fields` map, formatted by the type the schema reports. A
/// built-in the entity does not carry returns null rather than a placeholder —
/// the column is simply not rendered.
String? leadColumnText(Lead lead, LeadColumn column) {
  if (column.isCustom) {
    return _customText(lead.customFields[column.customKey], column.type);
  }

  switch (column.name) {
    case 'lead_name':
      return lead.name;
    case 'organization_name':
      return lead.company;
    case 'status':
      return lead.statusName.isNotEmpty ? lead.statusName : null;
    case 'lead_value':
      return lead.value;
    case 'lead_score':
      return lead.score > 0 ? '${lead.score}' : null;
    case 'lead_source':
      return lead.source;
    case 'products':
    case 'product':
      return lead.project;
    case 'lead_owner':
      return _userName(lead.owner);
    case 'assigned_team':
      return lead.assignedTeam;
    case 'mobile_no':
    case 'phone':
      return lead.phone;
    case 'whatsapp_no':
      return lead.whatsappNo;
    case 'territory':
      return lead.territory;
    case 'email':
      return lead.email;
    case 'website':
      return lead.website;
    case 'industry':
      return lead.industry;
    case 'location':
      return lead.location;
    case 'created_at':
      return lead.createdOn;
    case 'activity':
      return lead.time;
    case 'last_followup_at':
      return lead.lastFu;
    case 'stage_entered_at':
      // The mapper keeps this as an age, not a date — "19d in stage" is what
      // the pipeline reading calls for.
      return lead.statusDays > 0 ? '${lead.statusDays}d in stage' : null;
    case 'is_upsell':
      return lead.upsell ? 'Upsell' : null;
    default:
      // A column the entity does not carry (territory, annual_revenue, …).
      // Skipped rather than guessed at.
      return null;
  }
}

/// Formats a custom-field value by its declared type. Returns null for an unset
/// field — the API always keys visible custom fields, using `null` when there
/// is no value, so this is the common case rather than an error.
String? _customText(Object? value, String type) {
  if (value == null) return null;

  switch (type) {
    case 'boolean':
      return value == true ? 'Yes' : 'No';
    case 'date':
      final date = parseApiDate(value);
      return date != null ? absoluteDate(date) : _plainText(value);
    case 'multi_select':
      if (value is List) {
        final parts = value.map((v) => '$v').where((v) => v.isNotEmpty);
        return parts.isEmpty ? null : parts.join(', ');
      }
      return _plainText(value);
    default:
      return _plainText(value);
  }
}

String? _plainText(Object? value) {
  if (value is List) {
    final parts = value.map((v) => '$v').where((v) => v.isNotEmpty);
    return parts.isEmpty ? null : parts.join(', ');
  }
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) {
    // Whole decimals arrive as `5000.0`; a trailing `.0` reads as noise on a
    // list card.
    final text = value.toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

/// The owner's display name. An id the directory has not registered resolves
/// to the "Unknown" placeholder — skipped here, so the column drops out rather
/// than claiming the lead is owned by nobody.
String? _userName(String userId) {
  if (userId.isEmpty) return null;
  final name = MockUsers.of(userId).name.trim();
  return name.isEmpty || name == 'Unknown' ? null : name;
}
