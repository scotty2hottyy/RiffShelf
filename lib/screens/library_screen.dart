import 'package:file_picker/file_picker.dart';

import '../features/artwork/artwork_service.dart';

import 'package:flutter/material.dart';

import '../core/database/sqlite_tab_repository.dart';
import '../core/database/tab_repository.dart';
import '../core/models/saved_tab.dart';
import '../core/models/instrument_type.dart';
import '../features/library/edit_tab_screen.dart';
import '../features/import/tab_import_service.dart';
import '../features/import/guitar_pro_importer.dart';
import '../features/tabs/tab_detail_screen.dart';
import '../features/artwork/album_art.dart';

Future<int?> chooseTabTrack(
  BuildContext context,
  List<GuitarProTrackInfo> tracks,
) => showDialog<int>(
  context: context,
  builder: (context) => SimpleDialog(
    title: const Text('Choose a track'),
    children: [
      for (final track in tracks)
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, track.index),
          child: Text('${track.name} (${track.stringCount} strings)'),
        ),
    ],
  ),
);

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.repository, this.artworkService});
  final TabRepository? repository;
  final ArtworkService? artworkService;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final TabRepository repository =
      widget.repository ?? SqliteTabRepository.local();
  late Future<List<SavedTab>> tabs = repository.findTabs();
  final importer = const TabImportService();
  final search = TextEditingController();
  final filterCount = TextEditingController();
  final filterTuning = TextEditingController();
  final filterTags = TextEditingController();
  InstrumentType? instrument;
  InstrumentClassification? classification;
  int? stringCount;
  List<String>? tuning;
  Set<String> tags = {};
  bool favoritesOnly = false;

  void refresh() {
    setState(() {
      tabs = repository.findTabs(
        TabFilter(
          query: search.text,
          instrument: instrument,
          classification: classification,
          stringCount: stringCount,
          tuning: tuning,
          tags: tags,
          favoritesOnly: favoritesOnly,
        ),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    if (repository is SqliteTabRepository) {
      SqliteTabRepository.changes.addListener(refresh);
    }
  }

  @override
  void dispose() {
    if (repository is SqliteTabRepository) {
      SqliteTabRepository.changes.removeListener(refresh);
    }
    search.dispose();
    filterCount.dispose();
    filterTuning.dispose();
    filterTags.dispose();
    if (widget.repository == null) repository.close();
    super.dispose();
  }

  Future<void> importTab() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.any);
      if (result.isEmpty || !mounted) return;
      final file = result.single;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final ext = file.extension?.toLowerCase();
      if (!importer.supportsExtension(ext)) {
        throw const FormatException(
          'Unsupported file format. Choose a .txt, .gp3, .gp4, .gp5, or .gpx file.',
        );
      }
      SavedTab tab;
      var trackIndex = 0;
      if (ext == 'txt') {
        tab = importer.parseText(bytes, file.name);
      } else if (const ['gp3', 'gp4', 'gp5', 'gpx'].contains(ext)) {
        final document = importer.parseGuitarPro(bytes);
        var index = 0;
        if (document.tracks.length > 1) {
          final selected = await chooseTabTrack(context, document.tracks);
          if (selected == null || !mounted) return;
          index = selected;
        }
        trackIndex = index;
        tab = importer.convertTrack(document, index, file.name);
      } else {
        throw const FormatException('Unsupported file format.');
      }
      tab = tab.copyWith(importKey: importer.importKey(bytes, trackIndex));
      final saved = await repository.save(tab);
      ArtworkService.scheduleAutomatic(
        repository,
        saved,
        service: widget.artworkService,
      );
      if (!mounted) return;
      refresh();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tab imported')));
    } on DuplicateTabException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This file and track are already in your library.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message
          : 'Could not import this file.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: 'Choose file', onPressed: importTab),
        ),
      );
    }
  }

  Future<void> toggleFavorite(SavedTab tab) async {
    try {
      await repository.save(tab.copyWith(isFavorite: !tab.isFavorite));
      if (mounted) refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not update favorite. Please try again.'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => toggleFavorite(tab),
            ),
          ),
        );
      }
    }
  }

  Future<void> deleteTab(SavedTab tab) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete tab?'),
        content: Text('Delete “${tab.title}” from your library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await repository.delete(tab.id!);
      if (mounted) refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not delete tab. Please try again.'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => deleteTab(tab),
            ),
          ),
        );
      }
    }
  }

  Future<void> editTab(SavedTab tab) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditTabScreen(tab: tab, repository: repository),
      ),
    );
    if (changed == true && mounted) refresh();
  }

  void clearFilters() {
    search.clear();
    instrument = null;
    classification = null;
    stringCount = null;
    tuning = null;
    tags = {};
    favoritesOnly = false;
    refresh();
  }

  Future<void> showFilters() async {
    var selectedInstrument = instrument;
    var selectedClassification = classification;
    final count = filterCount..text = stringCount?.toString() ?? '';
    final tuningText = filterTuning..text = tuning?.join(' ') ?? '';
    final tagText = filterTags..text = tags.join(', ');
    var onlyFavorites = favoritesOnly;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Filter library'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<InstrumentType?>(
                  isExpanded: true,
                  initialValue: selectedInstrument,
                  decoration: const InputDecoration(labelText: 'Instrument'),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Any instrument'),
                    ),
                    DropdownMenuItem(
                      value: InstrumentType.guitar,
                      child: Text('Guitar'),
                    ),
                    DropdownMenuItem(
                      value: InstrumentType.bass,
                      child: Text('Bass'),
                    ),
                    DropdownMenuItem(
                      value: InstrumentType.other,
                      child: Text('Unknown / other'),
                    ),
                  ],
                  onChanged: (v) => update(() => selectedInstrument = v),
                ),
                DropdownButtonFormField<InstrumentClassification?>(
                  isExpanded: true,
                  initialValue: selectedClassification,
                  decoration: const InputDecoration(
                    labelText: 'Classification',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Any classification'),
                    ),
                    DropdownMenuItem(
                      value: InstrumentClassification.acoustic,
                      child: Text('Acoustic'),
                    ),
                    DropdownMenuItem(
                      value: InstrumentClassification.electric,
                      child: Text('Electric'),
                    ),
                    DropdownMenuItem(
                      value: InstrumentClassification.other,
                      child: Text('Unknown / other'),
                    ),
                  ],
                  onChanged: (v) => update(() => selectedClassification = v),
                ),
                TextField(
                  controller: count,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'String count',
                    hintText: 'Any',
                  ),
                ),
                TextField(
                  controller: tuningText,
                  decoration: const InputDecoration(
                    labelText: 'Tuning, low to high',
                    hintText: 'Any; e.g. E A D G',
                  ),
                ),
                TextField(
                  controller: tagText,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    helperText: 'All comma-separated tags must match',
                  ),
                ),
                SwitchListTile(
                  title: const Text('Favorites only'),
                  value: onlyFavorites,
                  onChanged: (v) => update(() => onlyFavorites = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final number = count.text.trim().isEmpty
                    ? null
                    : int.tryParse(count.text.trim());
                if (count.text.trim().isNotEmpty &&
                    (number == null || number < 1)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a positive string count.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (apply == true && mounted) {
      instrument = selectedInstrument;
      classification = selectedClassification;
      stringCount = int.tryParse(count.text.trim());
      tuning = tuningText.text.trim().isEmpty
          ? null
          : tuningText.text.trim().split(RegExp(r'[\s,]+'));
      tags = tagText.text
          .split(',')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toSet();
      favoritesOnly = onlyFavorites;
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF54E8D5) : const Color(0xFF006C65);
    return FutureBuilder<List<SavedTab>>(
      future: tabs,
      builder: (context, snapshot) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.library_music_outlined,
                    color: Color(0xFFD89635),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      'Library',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: importTab,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import Tab'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onChanged: (_) => refresh(),
                  decoration: InputDecoration(
                    labelText: 'Search title or artist',
                    prefixIcon: Icon(Icons.search, color: accent),
                    filled: true,
                    fillColor: dark ? const Color(0xFF101D20) : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Filters',
                onPressed: showFilters,
                icon: const Icon(Icons.filter_list),
              ),
              IconButton(
                tooltip: 'Clear filters',
                onPressed: clearFilters,
                icon: const Icon(Icons.filter_alt_off),
              ),
            ],
          ),
          if (instrument != null ||
              classification != null ||
              stringCount != null ||
              tuning != null ||
              tags.isNotEmpty ||
              favoritesOnly) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (instrument != null)
                  InputChip(
                    label: Text(instrument!.label),
                    deleteButtonTooltipMessage: 'Remove instrument filter',
                    onDeleted: () {
                      instrument = null;
                      refresh();
                    },
                  ),
                if (classification != null)
                  InputChip(
                    label: Text(classification!.name),
                    deleteButtonTooltipMessage: 'Remove classification filter',
                    onDeleted: () {
                      classification = null;
                      refresh();
                    },
                  ),
                if (stringCount != null)
                  InputChip(
                    label: Text('$stringCount strings'),
                    deleteButtonTooltipMessage: 'Remove string count filter',
                    onDeleted: () {
                      stringCount = null;
                      refresh();
                    },
                  ),
                if (tuning != null)
                  InputChip(
                    label: Text('Tuning: ${tuning!.join(' ')}'),
                    deleteButtonTooltipMessage: 'Remove tuning filter',
                    onDeleted: () {
                      tuning = null;
                      refresh();
                    },
                  ),
                for (final tag in tags)
                  InputChip(
                    label: Text('Tag: $tag'),
                    deleteButtonTooltipMessage: 'Remove $tag tag filter',
                    onDeleted: () {
                      tags = {...tags}..remove(tag);
                      refresh();
                    },
                  ),
                if (favoritesOnly)
                  InputChip(
                    label: const Text('Favorites'),
                    deleteButtonTooltipMessage: 'Remove favorites filter',
                    onDeleted: () {
                      favoritesOnly = false;
                      refresh();
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          if (snapshot.hasError) ...[
            const Text(
              'Could not load your library. Check storage and try again.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: refresh, child: const Text('Retry')),
            ),
          ] else if (!snapshot.hasData)
            const Center(child: Text('Loading library…'))
          else if (snapshot.data!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No saved tabs match. Import a tab or clear filters.',
              ),
            )
          else
            for (final tab in snapshot.data!)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LibraryCard(
                  tab: tab,
                  accent: accent,
                  onFavorite: () => toggleFavorite(tab),
                  onEdit: () => editTab(tab),
                  onDelete: () => deleteTab(tab),
                  onOpen: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => TabDetailScreen(
                          tab: tab,
                          repository: repository,
                          artworkService: widget.artworkService,
                        ),
                      ),
                    );
                    if (mounted) refresh();
                  },
                ),
              ),
        ],
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.tab,
    required this.accent,
    required this.onFavorite,
    required this.onEdit,
    required this.onDelete,
    required this.onOpen,
  });
  final SavedTab tab;
  final Color accent;
  final VoidCallback onFavorite, onEdit, onDelete, onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Material(
      color: dark ? const Color(0xFF101B1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: dark
              ? const Color(0xFF304247)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AlbumArt(tab: tab, size: 70),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tab.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tab.artist.isEmpty ? 'Unknown artist' : tab.artist,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tab.instrument == InstrumentType.other
                              ? 'Unknown instrument'
                              : tab.instrument.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  '${tab.stringCount} strings',
                  if (tab.tuning.isNotEmpty) tab.tuning.join(' '),
                  if (tab.trackName?.trim().isNotEmpty == true) tab.trackName!,
                  if (tab.source.trim().isNotEmpty) tab.source,
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              if (tab.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in tab.tags)
                      Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
              Row(
                children: [
                  Semantics(
                    toggled: tab.isFavorite,
                    child: IconButton(
                      tooltip: tab.isFavorite
                          ? 'Remove favorite'
                          : 'Add favorite',
                      onPressed: onFavorite,
                      icon: Icon(
                        tab.isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: tab.isFavorite ? accent : muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tab.isFavorite ? 'Favorite' : 'Add favorite',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Tab options',
                    onSelected: (action) {
                      if (action == 'edit') {
                        onEdit();
                      } else if (action == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit details')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
