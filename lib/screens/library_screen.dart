import 'package:flutter/material.dart';

import '../widgets/coming_soon_content.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonContent(
      title: 'Library',
      icon: Icons.library_music,
      description: 'Your saved tabs will be available here.',
    );
  }
}
