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
  List<SavedTab> relatedTracks = const [];

  // An import hash identifies a file; online keys identify a provider's song.
  (String, String, String)? trackGroup(SavedTab tab) {
    final key = tab.importKey;
    if (key == null) return null;
    final file = RegExp(r'^sha256:([0-9a-fA-F]{64}):track:[0-9]+$')
        .firstMatch(key);
    if (file != null) return ('file', file.group(1)!.toLowerCase(), '');
    final id = tab.sourceId;
    if (id != null &&
        id.isNotEmpty &&
        tab.source.isNotEmpty &&
        key.startsWith('online:${tab.source}:$id:') &&
        key.length > 'online:${tab.source}:$id:'.length) {
      return ('online', tab.source, id);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    loadRelatedTracks();
  }

  Future<void> loadRelatedTracks() async {
    final group = trackGroup(current);
    if (group == null || current.id == null || widget.repository == null) {
      return;
    }
    try {
      final all = await widget.repository!.findTabs();
      if (!mounted) return;
      final related = all
          .where((tab) => tab.id != null && trackGroup(tab) == group)
          .toList();
      if (related.length > 1 && related.any((tab) => tab.id == current.id)) {
        setState(() => relatedTracks = related);
      }
    } catch (_) {
      // Track navigation is optional and does not affect the saved tab viewer.
    }
  }

  late final ArtworkService artworkService =
      widget.artworkService ?? ArtworkService();

  void updateTrack(SavedTab updated) {
    setState(() {
      relatedTracks = [
        for (final track in relatedTracks)
          if (track.id == updated.id) updated else track,
      ];
      if (current.id == updated.id) current = updated;
    });
  }

  Future<void> chooseAlbum() async {
    final target = current;
    try {
      final candidates = await artworkService.candidates(
        target.artist,
        target.title,
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
      final updated = target.copyWith(artwork: metadata);
      await widget.repository!.save(updated);
      if (mounted) updateTrack(updated);
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
    final target = current;
    try {
      final updated = target.copyWith(clearArtwork: true);
      await widget.repository!.save(updated);
      if (mounted) updateTrack(updated);
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
            if (relatedTracks.length > 1) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                key: ValueKey('track-${tab.id}'),
                initialValue: tab.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Saved tracks'),
                items: [
                  for (final track in relatedTracks)
                    DropdownMenuItem(
                      value: track.id,
                      child: Text(
                        '${track.trackName?.isNotEmpty == true ? track.trackName : 'Track'} · ${track.instrument.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id == null || id == current.id) return;
                  final next = relatedTracks.firstWhere(
                    (track) => track.id == id,
                  );
                  setState(() {
                    // Retain album edits made before switching tracks.
                    relatedTracks = [
                      for (final track in relatedTracks)
                        if (track.id == current.id) current else track,
                    ];
                    current = next;
                    structured = next.hasStructuredContent;
                  });
                },
              ),
            ],
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
              StructuredTabViewer(key: ValueKey('viewer-${tab.id}'), tab: tab)
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
