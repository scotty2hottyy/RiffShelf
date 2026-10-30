import 'package:flutter/material.dart';

import '../widgets/coming_soon_content.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonContent(
      title: 'Practice',
      icon: Icons.music_note,
      description: 'Choose a tab and start a practice session.',
    );
  }
}
