import '../domain/entities/view_schema.dart';

/// Pure copy + display rules of the follow-up detail screen, mirroring the
/// webapp's `TaskDetailScreen` in follow-up mode (`taskDetailCopy.ts`,
/// `taskCell.tsx dueDateInfo`, `taskInfoFields.tsx`). Kept free of widgets so
/// they are unit-tested.

/// Webapp `deleteTaskMessage` for a follow-up.
String followupDeleteMessage(int? notes, int? files) {
  String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
  if (notes == null || files == null) {
    return "This permanently removes the follow-up together with its notes and files. This can't be undone.";
  }
  final parts = [
    if (notes > 0) count(notes, 'note', 'notes'),
    if (files > 0) count(files, 'file', 'files'),
  ];
  if (parts.isEmpty) return "This permanently removes the follow-up. This can't be undone.";
  return "This permanently removes the follow-up and its ${parts.join(' and ')}. This can't be undone.";
}

/// Webapp `reopenBlockedReason('follow-up')`.
const followupReopenOffHint =
    'Reopening completed follow-ups is turned off (Settings → CRM Settings → Task Settings).';

/// Webapp: the unlinked state of the actions band.
const followupUnlinkedText = 'Internal follow-up — not linked to any record.';

/// The actions-band button: "Mark complete", or "Mark as not done" once done.
String followupCompleteLabel(bool done) => done ? 'Mark as not done' : 'Mark complete';

String _clean(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s == 'null' ? '' : s;
}

/// Webapp `relatedModelLabel`: "lead" → "Lead", "organization_contact" →
/// "Contact", an unknown model → its words capitalised.
String followupRelatedModelLabel(String? model) => switch (_clean(model).toLowerCase()) {
      'lead' => 'Lead',
      'customer' => 'Customer',
      'product' => 'Product',
      'quotation' => 'Quote',
      'issue' => 'Ticket',
      'contact' || 'organization_contact' => 'Contact',
      'deal' => 'Deal',
      '' => 'Record',
      final m => () {
          final words = m.replaceAll('_', ' ').trim();
          return words[0].toUpperCase() + words.substring(1);
        }(),
    };

/// Webapp `relatedCaption`: the record type and its human reference
/// ("Lead · LD-0304") — never the record's UUID; just the type without one.
String followupRelatedCaption(Map<String, dynamic>? related) {
  final label = followupRelatedModelLabel(related?['model'] as String?);
  final reference = _clean(related?['reference']);
  return reference.isEmpty ? label : '$label · $reference';
}

/// The header subtitle: "<type> · <related label>".
String followupSubtitle(String type, Map<String, dynamic>? related) {
  final t = _clean(type);
  final label = _clean(related?['label']);
  final head = t.isEmpty ? 'Follow-up' : t;
  return label.isEmpty ? head : '$head · $label';
}

/// Webapp info row "Related To": `label · model`, or `—` without a label.
String followupRelatedRowValue(Object? related) {
  if (related is! Map) return '—';
  final label = _clean(related['label']);
  if (label.isEmpty) return '—';
  final model = _clean(related['model']);
  return model.isEmpty ? label : '$label · $model';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Webapp `dueDateInfo().label`: a `YYYY-MM-DD` due date as "18 Jun 2026".
/// Falls back to [fallback] (the list's own formatted date) when the record's
/// date is missing or unparseable.
String followupDueLabel(Object? dueIso, {String fallback = ''}) {
  final s = _clean(dueIso);
  final d = s.isEmpty ? null : DateTime.tryParse(s);
  if (d == null) return s.isEmpty ? fallback.trim() : s;
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// The tint of the header's due line (webapp `DUE_TONE`).
enum FollowupDueTone { none, warn, danger }

/// "2d overdue" / "Today" → danger, "In 3d" → warn, nothing → neutral.
FollowupDueTone followupDueTone(String caption) {
  final c = caption.trim();
  if (c.isEmpty) return FollowupDueTone.none;
  if (c.startsWith('In ')) return FollowupDueTone.warn;
  return FollowupDueTone.danger;
}

/// Webapp `present()`: an info row shows only when the record carries the
/// field (custom fields resolve against `custom_fields`).
bool followupRecordHasColumn(Map<String, dynamic> row, ViewColumn column) {
  if (column.isCustom) {
    final custom = row['custom_fields'];
    return custom is Map && custom.containsKey(column.customKey);
  }
  return row.containsKey(column.name);
}

/// The detail route of a linked record (webapp `RELATED_ROUTE`), or null when
/// the model has no detail page.
String? followupRelatedRoute(
  Map<String, dynamic>? related, {
  required String lead,
  required String customer,
  required String product,
  required String quote,
}) {
  final id = _clean(related?['id']);
  if (id.isEmpty) return null;
  final base = switch (_clean(related?['model']).toLowerCase()) {
    'lead' => lead,
    'customer' => customer,
    'product' => product,
    'quotation' => quote,
    _ => null,
  };
  return base == null ? null : '$base?id=$id';
}
