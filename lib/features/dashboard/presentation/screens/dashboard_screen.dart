import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/placeholder_screen.dart';

/// Dashboard — stub. Implemented in the module pass.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const PlaceholderScreen(title: 'Dashboard');
  }
}
