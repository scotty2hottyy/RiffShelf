import 'package:material_ui/material_ui.dart';

import '../core/database/sqlite_tab_repository.dart';
import '../core/database/tab_repository.dart';
import '../core/models/saved_tab.dart';
import '../features/tabs/practice_preparation_screen.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key, this.repository});
  final TabRepository? repository;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  late final TabRepository repository =
      widget.repository ?? SqliteTabRepository.local();
  late Future<List<SavedTab>> tabs = repository.findTabs();

  void refresh() => setState(() {
    tabs = repository.findTabs();
  });

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SavedTab>>(
      future: tabs,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Could not load your library. Check storage and try again.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(onPressed: refresh, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('Loading tabs…'));
        }
        final results = snapshot.data!;
        if (results.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Import or save a tab in your Library to start a practice '
                'session.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final tab = results[index];
            return ListTile(
              leading: Icon(
                Icons.play_circle_outline,
                color: tab.hasStructuredContent
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).disabledColor,
              ),
              title: Text(tab.title),
              subtitle: Text(
                '${tab.artist.isEmpty ? 'Unknown artist' : tab.artist} · '
                '${tab.instrument.label} · ${tab.stringCount} strings'
                '${tab.hasStructuredContent ? '' : ' · no structured data'}',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PracticePreparationScreen(tab: tab),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
