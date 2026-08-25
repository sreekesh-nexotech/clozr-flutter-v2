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

  /// The module-group **keys** this role grants (`crm`, `pmo`, …), lowercase.
  /// [caps] is the uppercased display form; these are what
  /// `module_groups[].group` takes on a write.
  final List<String> groupKeys;

  /// The record-scope **code** (`hierarchy`, `team`, …). [scope] is its label.
  /// Empty when the role has no lead-module scope to read — a seeded Admin,
  /// whose access is the `is_staff` bypass rather than a grant.
  final String scopeCode;

  /// The API's `is_deletable` — false for seeded roles **and** for custom roles
  /// that still have members, since deleting one would cascade their `UserRole`
  /// away (`roles.md` §6). [locked] is a different question: it mirrors
  /// `is_editable`, and a role can be editable but not deletable.
  final bool deletable;

  /// The API's `user_count` — members currently holding this role. The reason a
  /// custom role is undeletable, so the refusal can say how many.
  final int userCount;

  const Role({
    required this.id,
    required this.name,
    required this.locked,
    required this.scope,
    required this.desc,
    required this.caps,
    this.groupKeys = const [],
    this.scopeCode = '',
    this.deletable = true,
    this.userCount = 0,
  });

  @override
  List<Object?> get props => [id];
}
