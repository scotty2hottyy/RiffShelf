import 'package:flutter/material.dart';

import '../widgets/coming_soon_content.dart';

class TunerScreen extends StatelessWidget {
  const TunerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonContent(
      title: 'Tuner',
      icon: Icons.tune,
      description: 'Tune your instrument before you play.',
    );
  }
}
