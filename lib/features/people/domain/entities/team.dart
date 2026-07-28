import 'package:equatable/equatable.dart';

/// A team — a grouping of members by region or function. Teams carry no
/// visibility scope of their own (access flows from role + reporting
/// hierarchy). Mirrors the prototype's `teams` seed.
class Team extends Equatable {
  final String id;
  final String name;
  final String zone;
  final String lead; // member id
  final List<String> members; // member ids

  const Team({
    required this.id,
    required this.name,
    required this.zone,
    required this.lead,
    required this.members,
  });

  int get size => members.length;
  String get countLabel => '$size ${size == 1 ? 'member' : 'members'}';

  @override
  List<Object?> get props => [id];
}
