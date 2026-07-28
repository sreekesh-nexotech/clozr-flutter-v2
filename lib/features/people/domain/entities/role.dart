import 'package:equatable/equatable.dart';

/// A predefined (or custom) access role. Predefined roles are `locked` — a
/// fixed capability matrix and one visibility scope each. Mirrors the
/// prototype's `roles` seed.
class Role extends Equatable {
  final String id;
  final String name;
  final bool locked;
  final String scope; // visibility scope
  final String desc;
  final List<String> caps; // capability labels

  const Role({
    required this.id,
    required this.name,
    required this.locked,
    required this.scope,
    required this.desc,
    required this.caps,
  });

  @override
  List<Object?> get props => [id];
}
