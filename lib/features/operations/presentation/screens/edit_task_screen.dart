import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/placeholder_screen.dart';

/// Edit task — stub. Implemented in the module pass.
class EditTaskScreen extends ConsumerWidget {
  const EditTaskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const PlaceholderScreen(title: 'Edit task');
  }
}
