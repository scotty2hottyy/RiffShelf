import 'package:flutter/material.dart';

import '../../core/models/saved_tab.dart';
import '../../core/database/tab_repository.dart';
import '../artwork/album_art.dart';
import '../artwork/artwork_service.dart';
import 'practice_preparation_screen.dart';
import 'structured_tab_viewer.dart';

class TabDetailScreen extends StatefulWidget {
  const TabDetailScreen({
    super.key,
    required this.tab,
    this.repository,
    this.artworkService,
  });
  final SavedTab tab;
  final TabRepository? repository;
  final ArtworkService? artworkService;
  @override
  State<TabDetailScreen> createState() => _TabDetailScreenState();
}

class _TabDetailScreenState extends State<TabDetailScreen> {
  late SavedTab current = widget.tab;
  late bool structured = widget.tab.hasStructuredContent;
  late final ArtworkService artworkService =
      widget.artworkService ?? ArtworkService();

  Future<void> chooseAlbum() async {
    try {
      final candidates = await artworkService.candidates(
        current.artist,
        current.title,
      );
      if (!mounted) return;
      final selected = await showDialog<AlbumCandidate>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose an album'),
          children: candidates.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No albums found.'),
                  ),
                ]
              : [
                  for (final album in candidates)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, album),
                      child: Text(
                        '${album.title} — ${album.artist} · ${album.date ?? 'Date unknown'}',
                      ),
                    ),
                ],
        ),
      );
      if (selected == null) return;
      final metadata = await artworkService.select(selected);
      final updated = current.copyWith(artwork: metadata);
      await widget.repository!.save(updated);
      if (mounted) setState(() => current = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Album lookup or artwork download failed. Please try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> removeAlbum() async {
    try {
      final updated = current.copyWith(clearArtwork: true);
      await widget.repository!.save(updated);
      if (mounted) setState(() => current = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove the album.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = current;
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
                  builder: (_) => PracticePreparationScreen(tab: tab),
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
            AlbumArt(tab: tab, size: 180),
            if (widget.repository != null && tab.id != null) ...[
              Text(
                artworkMetadata(tab)?['title'] as String? ??
                    'No album selected',
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: chooseAlbum,
                    child: Text(
                      tab.artwork == null ? 'Choose album' : 'Change album',
                    ),
                  ),
                  if (tab.artwork != null)
                    TextButton(
                      onPressed: removeAlbum,
                      child: const Text('Remove album'),
                    ),
                ],
              ),
            ],
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
