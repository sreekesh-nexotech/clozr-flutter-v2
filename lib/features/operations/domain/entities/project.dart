import 'package:equatable/equatable.dart';

/// An Operations project. Fields mirror the prototype's `PROJ_SEED` records so
/// the mock data source maps directly and the shape is API-ready: when
/// `/projects` lands, deserialize JSON into this exact entity unchanged.
class Project extends Equatable {
  final String id;
  final String name;
  final String type;
  final String? company;
  final bool internal;
  final String status; // key into StatusMeta$.project
  final String pri; // High / Medium / Low
  final int progress; // 0..100
  final String manager; // user id
  final List<String> assignees; // user ids
  final bool myTask;
  final String start; // display, e.g. "02 May 2026"
  final String end;
  final String endISO; // "2026-08-30"
  final String cost; // display, e.g. "₹18L"
  final String visibility;
  final String method; // "Task-based" / "Manual"
  final String desc;

  const Project({
    required this.id,
    required this.name,
    required this.type,
    required this.company,
    required this.internal,
    required this.status,
    required this.pri,
    required this.progress,
    required this.manager,
    required this.assignees,
    required this.myTask,
    required this.start,
    required this.end,
    required this.endISO,
    required this.cost,
    required this.visibility,
    required this.method,
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
