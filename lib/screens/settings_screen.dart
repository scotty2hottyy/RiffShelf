import 'package:flutter/material.dart';

import '../widgets/coming_soon_content.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonContent(
      title: 'Settings',
      icon: Icons.settings,
      description: 'Manage your RiffShelf preferences.',
    );
  }
}
