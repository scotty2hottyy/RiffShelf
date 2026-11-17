import 'package:material_ui/material_ui.dart';

import '../../core/database/practice_session_repository.dart';
import '../../core/models/practice_session.dart';

class PracticeHistoryScreen extends StatefulWidget {
  const PracticeHistoryScreen({super.key, required this.repository});

  final PracticeSessionRepository repository;

  @override
  State<PracticeHistoryScreen> createState() => _PracticeHistoryScreenState();
}

class _PracticeHistoryScreenState extends State<PracticeHistoryScreen> {
  late Future<List<PracticeSession>> _sessions = widget.repository.getAll();
  bool _clearing = false;

  void _refresh() => setState(() => _sessions = widget.repository.getAll());

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear practice history?'),
        content: const Text('This permanently deletes all saved sessions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await widget.repository.clear();
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not clear practice history.')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  String _duration(int milliseconds) {
    final seconds = Duration(milliseconds: milliseconds).inSeconds;
    return '${seconds ~/ 60} min ${seconds % 60} sec';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Practice history')),
    body: FutureBuilder<List<PracticeSession>>(
      future: _sessions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load practice history.'),
                TextButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final sessions = snapshot.data!;
        if (sessions.isEmpty) {
          return const Center(
            child: Text('No saved sessions. Save one from a practice screen.'),
          );
        }
        final summary = PracticeHistorySummary(sessions);
        final localizations = MaterialLocalizations.of(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'All-time progress',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('${summary.sessions} saved sessions'),
            Text('Practice time: ${_duration(summary.durationMilliseconds)}'),
            Text('Sections marked complete: ${summary.completedSections}'),
            Text('Note-by-note confirmed notes: ${summary.confirmedNotes}'),
            if (summary.totalHits > 0 || summary.totalMisses > 0) ...[
              Text('Timed practice hits: ${summary.totalHits}'),
              Text('Timed practice misses: ${summary.totalMisses}'),
              if (summary.averageAccuracy != null)
                Text(
                  'Timed practice accuracy: ${summary.averageAccuracy!.toStringAsFixed(1)}%',
                ),
              const Text(
                'Timed practice measures single-note pitch accuracy within timing tolerance windows. '
                'Note-by-note mode and chords do not assess rhythm or missed notes.',
              ),
            ] else
              const Text(
                'Timing, note-match and combined accuracy are unavailable: '
                'these modes do not measure rhythm or missed notes.',
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _clearing ? null : _clear,
                child: const Text('Clear history'),
              ),
            ),
            for (final session in sessions)
              Card(
                child: ListTile(
                  title: Text(session.title),
                  subtitle: Text(
                    [
                      if (session.artist.isNotEmpty) session.artist,
                      localizations.formatFullDate(session.savedAt.toLocal()),
                      'Practice time: ${_duration(session.durationMilliseconds)}',
                      if (session.startMeasure != null &&
                          session.endMeasure != null)
                        'Selected measures: ${session.startMeasure}–${session.endMeasure}',
                      session.markedComplete
                          ? 'Section marked complete by you'
                          : 'Section not marked complete',
                      if (session.hits != null && session.misses != null)
                        'Timed practice: ${session.hits} hits, ${session.misses} misses (${session.accuracy?.toStringAsFixed(1) ?? '0.0'}% accuracy)'
                      else
                        'Note-by-note confirmed notes: ${session.confirmedNotes}',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
        );
      },
    ),
  );
}
