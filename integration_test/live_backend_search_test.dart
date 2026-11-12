import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:riffshelf/screens/discover_screen.dart';

/// Optional manual test: requires a running backend and real Songsterr access.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Discover receives live backend results', (tester) async {
    const baseUrl = String.fromEnvironment('RIFFSHELF_API_BASE_URL');
    expect(
      baseUrl,
      isNotEmpty,
      reason: 'Pass --dart-define=RIFFSHELF_API_BASE_URL=...',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DiscoverScreen())),
    );
    await tester.enterText(find.byType(TextField), 'Come As You Are');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('Come As You Are'), findsWidgets);
    expect(find.textContaining('Nirvana'), findsWidgets);
    expect(find.textContaining('Songsterr'), findsWidgets);
  });
}
