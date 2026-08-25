import 'package:equatable/equatable.dart';

/// An Operations project. Fields mirror the prototype's `PROJ_SEED` records so
/// the mock data source maps directly and the shape is API-ready: when
/// `/projects` lands, deserialize JSON into this exact entity unchanged.
class Project extends Equatable {
  final String id;

  /// `naming_series` — the human code (`PRJ-1010`). [id] stays the UUID, which
  /// is what every endpoint keys on but is not something to show a user.
  final String code;

  /// The server's own overdue verdict (`is_overdue`), which knows the real date
  /// and the org's closed statuses. Null in mock mode.
  final bool? isOverdue;
  final String name;
  final String type;
  final String? company;
  final bool internal;
  final String status; // key into StatusMeta$.project

  /// The org's `project_status_id`, which a status write has to send — the
  /// folded [status] and the display [statusName] are both unusable for that.
  final String statusId;

  /// The org's own status name ("Planning", "In Delivery"), as
  /// `/projects/projects/` reports it in `status_name`.
  ///
  /// Kept alongside the folded [status] because the two answer different
  /// questions: [status] picks the colour and the built-in vocabulary, this is
  /// what the org calls it — and what the status tabs and the drawer facet match
  /// on, since both are now driven by `/projects/project-statuses/`. Empty in
  /// mock mode and on a row that carries no name.
  final String statusName;
  final String pri; // High / Medium / Low
  final int progress; // 0..100
  final String manager; // user id
  final List<String> assignees; // user ids
  final bool myTask;
  final String start; // display, e.g. "02 May 2026"
  final String end;
  final String endISO; // "2026-08-30"
  final String cost; // display, e.g. "₹18L"

  /// `estimated_costing` in rupees, unformatted.
  ///
  /// [cost] is a **display** string and `formatInr` abbreviates it — ₹25,00,000
  /// renders as "₹25L" — so digits cannot be recovered from it. The edit form
  /// prefills from this; prefilling from [cost] and stripping the non-digits
  /// turned ₹25 lakh into ₹25 on every save. Mirrors `Product.priceNum`.
  final double costNum;
  final String visibility;
  final String method; // "Task-based" / "Manual"

  /// `assigned_team_name` — the project's team, empty for "No team".
  ///
  /// Detail-only, like [cost], [visibility], [method] and [assignees]: the
  /// list's slim rows drop it. The Details tab used to fall back to the
  /// manager's seed team, and then to the literal "Team Kochi".
  final String team;

  /// `is_archived` — archived projects are hidden from the list unless
  /// `?include_archived=true`. Drives the menu's Archive/Restore label.
  final bool isArchived;

  final String desc;

  const Project({
    required this.id,
    this.code = '',
    this.isOverdue,
    required this.name,
    required this.type,
    required this.company,
    required this.internal,
    required this.status,
    this.statusName = '',
    this.statusId = '',
    required this.pri,
    required this.progress,
    required this.manager,
    required this.assignees,
    required this.myTask,
    required this.start,
    required this.end,
    required this.endISO,
    required this.cost,
    this.costNum = 0,
    required this.visibility,
    required this.method,
    this.team = '',
    this.isArchived = false,
    required this.desc,
  });

  /// The prototype's `projInvolved` — manager, assignee or flagged "my task".
  bool get isMine => manager == 'me' || assignees.contains('me') || myTask;

  /// Completed / cancelled projects are read-only in the prototype.
  bool get isLocked => status == 'completed' || status == 'cancelled';

  Project copyWith({String? status, int? progress}) => Project(
        id: id,
        name: name,
        type: type,
        company: company,
        internal: internal,
        status: status ?? this.status,
        statusName: statusName,
        statusId: statusId,
        pri: pri,
        progress: progress ?? this.progress,
        manager: manager,
        assignees: assignees,
        myTask: myTask,
        start: start,
        end: end,
        endISO: endISO,
        cost: cost,
        visibility: visibility,
        method: method,
        desc: desc,
      );

  @override
  List<Object?> get props => [id];
}
