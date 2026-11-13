import 'package:material_ui/material_ui.dart';

import '../../core/models/saved_tab.dart';
import '../../core/models/tuning.dart';
import '../../screens/tuner_screen.dart';
import '../tuner/pitch_detector.dart';
import 'practice_session_screen.dart';

/// Keeps the chosen arrangement in place while the player tunes or skips ahead.
class PracticePreparationScreen extends StatelessWidget {
  const PracticePreparationScreen({super.key, required this.tab});

  final SavedTab tab;

  TuningPreset? get _tuning {
    if (tab.tuning.length != tab.stringCount || tab.tuning.isEmpty) return null;
    // Do not guess octaves for text imports or unknown tuning metadata.
    if (tab.tuning.any((note) {
      final midi = midiFromNoteName(note);
      return midi == null || midi < 0 || midi > 127;
    })) {
      return null;
    }
    return TuningPreset(
      name: 'Arrangement tuning',
      instrument: TunerInstrument.fromTabInstrument(tab.instrument),
      notes: tab.tuning,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tuning = _tuning;
    return Scaffold(
      appBar: AppBar(title: const Text('Get ready to practice')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tab.title, style: Theme.of(context).textTheme.headlineSmall),
          if (tab.artist.isNotEmpty) Text(tab.artist),
          if (tab.trackName?.isNotEmpty == true) Text(tab.trackName!),
          Text('${tab.instrument.label} · ${tab.stringCount} strings'),
          const SizedBox(height: 16),
          Text('Tuning, low to high: ${tab.tuning.join(' ')}'),
          const SizedBox(height: 16),
          if (!tab.hasUsableContent)
            const Text('This tab has no playable notes.')
          else ...[
            if (tuning == null)
              const Text(
                'This arrangement has incomplete tuning information. '
                'Check your tuning manually before practicing.',
              ),
            OutlinedButton.icon(
              onPressed: tuning == null
                  ? null
                  : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text('Tune · ${tab.title}')),
                          body: TunerScreen(preset: tuning),
                          bottomNavigationBar: SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: FilledButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Done tuning'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              icon: const Icon(Icons.tune),
              label: const Text('Tune instrument'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => PracticeSessionScreen(tab: tab),
                ),
              ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start practice'),
            ),
            const Text('Already in tune? Start practice to skip tuning.'),
          ],
        ],
      ),
    );
  }
}
