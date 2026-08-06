import '../../../../core/filters/filter_models.dart';
import '../../domain/entities/crm_catalog.dart';

/// Translates the Follow-ups drawer into `/crm/tasks/` query params, so the
/// filters — including the is / is-not toggles — are resolved by the server
/// over every follow-up rather than by the app over the rows it loaded.
///
/// **The status params are asymmetric**, verified against a live org:
///
/// * `status__in` takes the status **name**, case-insensitively. A uuid
///   silently matches nothing.
/// * `status__not` takes the status **id**. A name returns a 500.
///
/// So the two halves of one toggle are encoded differently. Everything else
/// (`task_type__in` / `__not`) takes names on both sides.
class FollowupFilterCodec {
  const FollowupFilterCodec({this.statuses = const [], this.currentUserId});

  /// The org's task statuses, used to resolve a drawer option (a case-folded
  /// name) to the id `status__not` requires.
  final List<CatalogOption> statuses;

  /// The signed-in user's uuid, so the drawer's `'me'` sentinel can be written
  /// out as a real id.
  final String? currentUserId;

  /// The param dict for [v]. Empty when nothing is applied.
  ///
  /// `companies` is deliberately absent: a follow-up row carries no company —
  /// the value is the linked record's own name — and there is no param for it.
  /// That one section stays a local match over the server-filtered set.
  Map<String, dynamic> encode(FilterValues v) {
    final out = <String, dynamic>{};

    _choice(out, v.choice('types'), 'task_type', (id) => id);
    _choice(
      out,
      v.choice('statuses'),
      'status',
      // `__in` wants the name the option id already is; `__not` wants the id.
      (id) => id,
      notResolve: _statusId,
    );
    _choice(out, v.choice('owners'), 'assigned_to', _userId);

    final due = v.date('due');
    if (due != null && due.isActive) {
      final (from, to) =
          due.chip != null ? FilterMatch.chipRange(due.chip!) : (due.from, due.to);
      if (from != null) out['due_date_after'] = _ymd(from);
      if (to != null) out['due_date_before'] = _ymd(to);
    }

    return out;
  }

  void _choice(
    Map<String, dynamic> out,
    ChoiceValue? value,
    String param,
    String? Function(String optionId) resolve, {
    String? Function(String optionId)? notResolve,
  }) {
    if (value == null || value.ids.isEmpty) return;
    final map = value.isNot ? (notResolve ?? resolve) : resolve;
    final ids = <String>[];
    for (final id in value.ids) {
      final resolved = map(id);
      if (resolved != null && resolved.isNotEmpty) ids.add(resolved);
    }
    // Every value failed to resolve — omit the key rather than send an empty
    // one, which would filter to nothing server-side.
    if (ids.isEmpty) return;
    out['$param${value.isNot ? '__not' : '__in'}'] = ids.join(',');
  }

  /// Drawer option id (a case-folded status name) → `crm_task_status_id`.
  String? _statusId(String optionId) {
    for (final s in statuses) {
      if (s.key == optionId) return s.id;
    }
    return null;
  }

  String? _userId(String id) => id == 'me' ? currentUserId : id;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
