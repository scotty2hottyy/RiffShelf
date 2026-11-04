import 'package:flutter/material.dart';

import '../../core/models/saved_tab.dart';
import 'practice_session_screen.dart';
import 'structured_tab_viewer.dart';

class TabDetailScreen extends StatefulWidget {
  const TabDetailScreen({super.key, required this.tab});
  final SavedTab tab;
  @override
  State<TabDetailScreen> createState() => _TabDetailScreenState();
}

class _TabDetailScreenState extends State<TabDetailScreen> {
  late bool structured = widget.tab.hasStructuredContent;
  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    return Scaffold(
      appBar: AppBar(
        title: Text(tab.title),
        actions: [
          if (tab.hasStructuredContent)
            IconButton(
              tooltip: 'Practice',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PracticeSessionScreen(tab: tab),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tab.artist.isEmpty ? 'Unknown artist' : tab.artist,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              [
                tab.instrument.label,
                if (tab.trackName?.isNotEmpty == true) tab.trackName!,
                'Tuning: ${tab.tuning.join(' ')}',
                if (tab.bpm != null) '${tab.bpm} BPM',
              ].join(' · '),
            ),
            const SizedBox(height: 20),
            if (tab.hasStructuredContent && tab.hasTextContent)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Structured')),
                  ButtonSegment(value: false, label: Text('ASCII')),
                ],
                selected: {structured},
                onSelectionChanged: (value) =>
                    setState(() => structured = value.first),
              ),
            if (!tab.hasUsableContent)
              const Text('No compatible tablature is available.')
            else if (structured)
              StructuredTabViewer(tab: tab)
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  tab.asciiTab,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
