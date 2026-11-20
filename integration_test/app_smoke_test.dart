import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:riffshelf/app.dart';
import 'package:riffshelf/core/theme_provider.dart';

/// On-device smoke test for the full app shell.
///
/// Runs offline and never starts the microphone, so it is safe for CI
/// emulators and simulators. Run locally with:
///
///   flutter test integration_test/app_smoke_test.dart -d `<device-id>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ThemeProvider themeProvider;

  Future<void> launchApp(WidgetTester tester) async {
    themeProvider = ThemeProvider();
    await themeProvider.init();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: const RiffShelfApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder destination(String label) => find.byWidgetPredicate(
    (widget) => widget is NavigationDestination && widget.label == label,
  );

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(destination(label));
    await tester.pumpAndSettle();
  }

  testWidgets('launches on Discover with every destination', (tester) async {
    await launchApp(tester);

    expect(find.text('Song or artist'), findsOneWidget);
    const labels = ['Discover', 'Library', 'Practice', 'Tuner', 'Settings'];
    for (final label in labels) {
      expect(destination(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('each destination shows its main control', (tester) async {
    await launchApp(tester);

    await openTab(tester, 'Library');
    expect(find.text('Import Tab'), findsOneWidget);

    await openTab(tester, 'Practice');
    expect(find.text('Practice history'), findsOneWidget);

    await openTab(tester, 'Tuner');
    await tester.ensureVisible(find.text('Start tuning'));
    expect(find.text('Start tuning'), findsOneWidget);

    await openTab(tester, 'Settings');
    expect(find.text('Light Mode'), findsOneWidget);
    expect(find.text('Show all album types'), findsOneWidget);

    await openTab(tester, 'Discover');
    expect(find.text('Song or artist'), findsOneWidget);
  });

  testWidgets('opens and closes practice history', (tester) async {
    await launchApp(tester);

    await openTab(tester, 'Practice');
    await tester.tap(find.text('Practice history'));
    // History loads from the on-device database with a spinner, so wait for
    // the real query instead of relying on pumpAndSettle alone.
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Practice history'),
      ),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(destination('Practice'), findsOneWidget);
  });

  testWidgets('switches theme and saves the choice', (tester) async {
    await launchApp(tester);
    final startedLight = themeProvider.isLightMode;
    addTearDown(() => themeProvider.setLightMode(startedLight));

    await openTab(tester, 'Settings');
    // The album-type toggle is a CupertinoSwitch, so this finds only the
    // theme switch.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(themeProvider.isLightMode, !startedLight);
    final context = tester.element(find.text('Light Mode'));
    expect(
      Theme.of(context).brightness,
      startedLight ? Brightness.dark : Brightness.light,
    );

    final reloaded = ThemeProvider();
    await reloaded.init();
    expect(reloaded.isLightMode, !startedLight);
  });
}
