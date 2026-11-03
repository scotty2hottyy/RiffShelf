import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riffshelf/features/search/data/songsterr_provider.dart';
import 'package:riffshelf/features/search/domain/tab_source_provider.dart';

/// Manual iOS smoke test. Calls Songsterr directly, without the backend.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('direct Songsterr search returns Nirvana songs', (_) async {
    final provider = SongsterrProvider();
    try {
      final results = await provider.search(
        const TabSearchQuery(text: 'nirvana'),
      );
      expect(results, isNotEmpty);
      expect(
        results.any((song) => song.artist.toLowerCase().contains('nirvana')),
        isTrue,
      );
    } finally {
      // Only bounded endpoint/status/phase metadata; no query, body, or errors.
      // ignore: avoid_print
      print(provider.diagnosticReport(''));
    }
  });
}
