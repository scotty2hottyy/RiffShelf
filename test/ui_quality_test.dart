import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:riffshelf/app.dart';
import 'package:riffshelf/core/theme_provider.dart';
import 'package:riffshelf/core/models/instrument_type.dart';
import 'package:riffshelf/core/models/saved_tab.dart';
import 'package:riffshelf/core/models/tab_structure.dart';
import 'package:riffshelf/features/tabs/tab_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  for (final size in [
    const Size(320, 640),
    const Size(375, 812),
    const Size(640, 320),
    const Size(1024, 768),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final light in [false, true]) {
        for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
          testWidgets(
            'navigation layouts ${size.width}x${size.height} at $scale ${light ? 'light' : 'dark'} $platform',
            (tester) async {
              debugDefaultTargetPlatformOverride = platform;
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = size;
              tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(() {
                debugDefaultTargetPlatformOverride = null;
                tester.view.resetPhysicalSize();
                tester.view.resetDevicePixelRatio();
                tester.view.resetPadding();
                tester.platformDispatcher.clearTextScaleFactorTestValue();
              });
              SharedPreferences.setMockInitialValues({'app_theme_mode': light});
              final theme = ThemeProvider();
              await theme.init();
              await tester.pumpWidget(
                ChangeNotifierProvider.value(
                  value: theme,
                  child: const RiffShelfApp(),
                ),
              );
              await tester.pumpAndSettle();
              for (final destination in [
                'Discover',
                'Practice',
                'Tuner',
                'Library',
                'Settings',
              ]) {
                await tester.tap(
                  find.descendant(
                    of: find.byType(NavigationBar),
                    matching: find.text(destination),
                  ),
                );
                await tester.pumpAndSettle();
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '$destination $size $scale',
                );
              }
              debugDefaultTargetPlatformOverride = null;
            },
          );
        }
      }
    }
  }

  testWidgets(
    'theme switch changes appearance and primary contrast remains readable',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeProvider();
      await theme.init();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: theme, child: const RiffShelfApp()),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Settings'),
        ),
      );
      await tester.pumpAndSettle();
      expect(theme.isLightMode, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(theme.isLightMode, isTrue);
      final scheme = theme.getTheme(true).colorScheme;
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
      }

      expect(
        contrast(scheme.primary, scheme.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(scheme.primary, Colors.white), greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    },
  );
  for (final light in [false, true]) {
    testWidgets(
      'tab detail supports two-times text at 320px in ${light ? 'light' : 'dark'} mode',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        const tab = SavedTab(
          title: 'Test song',
          artist: 'Artist',
          source: 'Local',
          sourceUrl: '',
          instrument: InstrumentType.bass,
          stringCount: 4,
          tuning: ['E', 'A', 'D', 'G'],
          asciiTab: 'G|--0--|',
          measures: [
            TabMeasure(
              number: 1,
              beats: [
                TabBeat(
                  position: 0,
                  notes: [TabNote(stringNumber: 1, fret: 3)],
                ),
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeProvider().getTheme(light),
            home: const TabDetailScreen(tab: tab),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('ASCII'));
        await tester.tap(find.text('ASCII'));
        await tester.pumpAndSettle();
        expect(find.text('G|--0--|'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
