import 'package:flutter/material.dart';

import '../widgets/coming_soon_content.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonContent(
      title: 'Discover',
      icon: Icons.explore,
      description: 'Find guitar and bass tabs to play.',
    );
  }
}
