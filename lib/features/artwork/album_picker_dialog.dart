import 'package:material_ui/material_ui.dart';

import 'artwork_service.dart';

/// Interactive album picker dialog supporting studio-album filtering,
/// duplicate release grouping, and temporary override to view all releases.
class AlbumPickerDialog extends StatefulWidget {
  const AlbumPickerDialog({
    super.key,
    required this.allCandidates,
    this.initialShowAll = false,
  });

  final List<AlbumCandidate> allCandidates;
  final bool initialShowAll;

  @override
  State<AlbumPickerDialog> createState() => _AlbumPickerDialogState();
}

class _AlbumPickerDialogState extends State<AlbumPickerDialog> {
  late bool overrideShowAllReleases = false;
  late bool showAllTypes = widget.initialShowAll;

  @override
  Widget build(BuildContext context) {
    if (widget.allCandidates.isEmpty) {
      return SimpleDialog(
        title: const Text('Choose an album'),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No albums found. Try another search after checking the song and artist.',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final List<AlbumCandidate> visible;
    if (overrideShowAllReleases) {
      visible = widget.allCandidates;
    } else if (showAllTypes) {
      visible = ArtworkService.groupCandidates(widget.allCandidates);
    } else {
      final studioOnly = ArtworkService.filterStudioAlbums(
        widget.allCandidates,
      );
      visible = ArtworkService.groupCandidates(studioOnly);
    }

    if (visible.isEmpty) {
      return SimpleDialog(
        title: const Text('Choose an album'),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No studio albums found. Try showing all releases, or check the song and artist.',
            ),
          ),
          SimpleDialogOption(
            onPressed: () => setState(() => overrideShowAllReleases = true),
            child: const Text('Show all releases'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return SimpleDialog(
      title: const Text('Choose an album'),
      children: [
        for (final album in visible)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, album),
            child: Text(
              '${album.title} — ${album.artist} · ${album.date ?? 'Date unknown'}',
            ),
          ),
        if (!overrideShowAllReleases)
          SimpleDialogOption(
            onPressed: () => setState(() => overrideShowAllReleases = true),
            child: const Text('Show all releases'),
          )
        else if (!widget.initialShowAll)
          SimpleDialogOption(
            onPressed: () => setState(() => overrideShowAllReleases = false),
            child: const Text('Studio albums only'),
          ),
      ],
    );
  }
}
