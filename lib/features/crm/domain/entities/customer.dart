import 'package:equatable/equatable.dart';

/// A CRM customer (a converted / won account). Fields mirror the prototype's
/// `customersRaw` seed — the same shape as [Lead] plus `since` (the month the
/// account was won). API-ready: deserialize `/customers` JSON into this entity.
class Customer extends Equatable {
  final String id;
  final String? leadId;
  final String name;
  final String initials;
  final String? company;
  final String project;
  final String value; // display, e.g. "₹18L"
  final int valueNum; // sortable
  final String status; // key into StatusMeta$.customer
  final String since; // "Dec 2025"
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

  const Customer({
    required this.id,
    required this.leadId,
    required this.name,
    required this.initials,
    required this.company,
    required this.project,
    required this.value,
    required this.valueNum,
    required this.status,
    required this.since,
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
  });

  bool get isMine => owner == 'me' || team.contains('me');
  bool get isUpsell => status == 'upsell';

  @override
  List<Object?> get props => [id];
}
