import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Subtask detail (#12). Reached by tapping a subtask row inside Task Detail.
///
/// NOTE: stub — the Operations build agent implements the full page (title,
/// done toggle, assignee, due date, parent-task back link, notes thread). The
/// route + nav metadata are already registered so the app compiles.
class SubtaskDetailScreen extends ConsumerWidget {
  const SubtaskDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      body: Center(child: Text('Subtask')),
    );
  }
}
