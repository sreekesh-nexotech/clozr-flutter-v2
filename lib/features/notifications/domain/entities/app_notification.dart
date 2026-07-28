import 'package:flutter/material.dart';

/// A notification row. `targetKind`/`targetId` describe the deep-link
/// destination; the presentation maps them to a route. Ported 1:1 from the
/// prototype's `notifs` seed.
class AppNotification {
  final String id;
  final String category; // leads/payments/tasks/system/ops/help/training
  final bool urgent;
  final String day; // today / yesterday / earlier
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String body;
  final String time; // "7m", "1d"
  final bool unread;
  final String targetKind; // lead/payment/followup/opstask/ticket/quote/project/list/none
  final String? targetId;

  const AppNotification({
    required this.id,
    required this.category,
    required this.urgent,
    required this.day,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.body,
    required this.time,
    required this.unread,
    required this.targetKind,
    this.targetId,
  });

  AppNotification copyWith({bool? unread}) => AppNotification(
        id: id,
        category: category,
        urgent: urgent,
        day: day,
        icon: icon,
        iconColor: iconColor,
        iconBg: iconBg,
        title: title,
        body: body,
        time: time,
        unread: unread ?? this.unread,
        targetKind: targetKind,
        targetId: targetId,
      );

  bool get hasTarget => targetKind != 'none';

  /// Category label shown in the row meta line.
  String get categoryLabel {
    switch (category) {
      case 'leads':
        return 'Leads';
      case 'payments':
        return 'Payments';
      case 'tasks':
        return 'Tasks';
      case 'ops':
        return 'Operations';
      case 'help':
        return 'Helpdesk';
      case 'training':
        return 'Training';
      default:
        return 'System';
    }
  }
}
