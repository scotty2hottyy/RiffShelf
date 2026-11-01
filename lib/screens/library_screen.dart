import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/database/sqlite_tab_repository.dart';
import '../core/database/tab_repository.dart';
import '../core/models/saved_tab.dart';
import '../core/models/instrument_type.dart';
import '../features/library/edit_tab_screen.dart';
import '../features/import/tab_import_service.dart';
import '../features/import/guitar_pro_importer.dart';
import '../features/tabs/tab_detail_screen.dart';

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
  const LibraryScreen({super.key, this.repository});
  final TabRepository? repository;
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
    if (widget.repository == null) {
      SqliteTabRepository.changes.addListener(refresh);
    }
  }

  @override
  void dispose() {
    if (widget.repository == null) {
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
      await repository.save(tab);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> toggleFavorite(SavedTab tab) async {
    try {
      await repository.save(tab.copyWith(isFavorite: !tab.isFavorite));
      if (mounted) refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update favorite.')),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not delete tab.')));
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
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text('Library', style: Theme.of(context).textTheme.headlineSmall),
            FilledButton.icon(
              onPressed: importTab,
              icon: const Icon(Icons.upload_file),
              label: const Text('Import Tab'),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                onChanged: (_) => refresh(),
                decoration: const InputDecoration(
                  labelText: 'Search title or artist',
                  prefixIcon: Icon(Icons.search),
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
      ),
      Expanded(
        child: FutureBuilder<List<SavedTab>>(
          future: tabs,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Could not load your library.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: Text('Loading library…'));
            }
            final results = snapshot.data!;
            if (results.isEmpty) {
              return const Center(
                child: Text(
                  'No saved tabs match. Import a tab or clear filters.',
                ),
              );
            }
            return ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final tab = results[index];
                final label = tab.instrument == InstrumentType.other
                    ? 'Unknown instrument'
                    : tab.instrument.label;
                return ListTile(
                  title: Text(tab.title),
                  subtitle: Text(
                    '${tab.artist.isEmpty ? 'Unknown artist' : tab.artist} · $label · ${tab.stringCount} strings · ${tab.tuning.join(' ')}${tab.tags.isEmpty ? '' : '\n${tab.tags.join(', ')}'}',
                  ),
                  isThreeLine: tab.tags.isNotEmpty,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: tab.isFavorite
                            ? 'Remove favorite'
                            : 'Add favorite',
                        onPressed: () => toggleFavorite(tab),
                        icon: Icon(
                          tab.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: tab.isFavorite
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Tab options',
                        onSelected: (action) {
                          if (action == 'edit') {
                            editTab(tab);
                          } else {
                            deleteTab(tab);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit details'),
                          ),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => TabDetailScreen(tab: tab),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}
