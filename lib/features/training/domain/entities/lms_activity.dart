import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

/// A single Recent-Activity feed row. Mirrors the prototype's `LMS_ACTIVITY`
/// records (`{ dot, who, what, time }`).
class LmsActivity extends Equatable {
  final Color dot;
  final String who;
  final String what;
  final String time;

  const LmsActivity({
    required this.dot,
    required this.who,
    required this.what,
    required this.time,
  });

  @override
  List<Object?> get props => [who, what, time];
}
