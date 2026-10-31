import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/database/sqlite_tab_repository.dart';
import '../core/database/tab_repository.dart';
import '../core/models/saved_tab.dart';
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
  @override
  void dispose() {
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
        tab = importer.convertTrack(document, index, file.name);
      } else {
        throw const FormatException('Unsupported file format.');
      }
      await repository.save(tab);
      if (!mounted) return;
      setState(() => tabs = repository.findTabs());
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tab imported')));
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message
          : 'Could not import this file.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text('Library', style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            FilledButton.icon(
              onPressed: importTab,
              icon: const Icon(Icons.upload_file),
              label: const Text('Import Tab'),
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
            if (snapshot.data!.isEmpty) {
              return const Center(
                child: Text('Your saved tabs will be available here.'),
              );
            }
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final tab = snapshot.data![index];
                return ListTile(
                  title: Text(tab.title),
                  subtitle: Text(
                    tab.artist.isEmpty
                        ? tab.instrument.label
                        : '${tab.artist} · ${tab.instrument.label}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
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
