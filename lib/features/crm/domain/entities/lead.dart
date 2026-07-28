import 'package:equatable/equatable.dart';

/// A CRM lead. Fields mirror the prototype's seed `raw` records so the mock
/// data source maps directly, and the shape is API-ready: when `/leads` lands,
/// deserialize JSON into this exact entity and the UI is unchanged.
class Lead extends Equatable {
  final String id;
  final String name;
  final String initials;
  final String? company;
  final String project;
  final String value; // display, e.g. "₹18L"
  final int valueNum; // sortable
  final String status; // key into StatusMeta$.lead
  final int statusDays;
  final int score;
  final String source;
  final String owner; // user id
  final List<String> team; // user ids
  final String phone;
  final String email;
  final String website;
  final String industry;
  final String location;
  final String createdOn;
  final String time; // "2h ago"
  final String lastFu;
  final int notif;
  final bool upsell;
  final String? fromCustomerId;

  const Lead({
    required this.id,
    required this.name,
    required this.initials,
    required this.company,
    required this.project,
    required this.value,
    required this.valueNum,
    required this.status,
    required this.statusDays,
    required this.score,
    required this.source,
    required this.owner,
    required this.team,
    required this.phone,
    required this.email,
    required this.website,
    required this.industry,
    required this.location,
    required this.createdOn,
    required this.time,
    required this.lastFu,
    required this.notif,
    this.upsell = false,
    this.fromCustomerId,
  });

  bool get isMine => owner == 'me' || team.contains('me');

  @override
  List<Object?> get props => [id];
}
