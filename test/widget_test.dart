import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:riffshelf/app.dart';
import 'package:riffshelf/core/theme_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Widget buildTestApp() {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const RiffShelfApp(),
    );
  }

  testWidgets('shows all navigation destinations and the initial screen', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp());

    expect(find.text('Discover'), findsWidgets);
    expect(find.text('Song or artist'), findsOneWidget);
    expect(find.text('Practice'), findsWidgets);
    expect(find.text('Tuner'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('switches tabs and restores the selected tab', (tester) async {
    await tester.pumpWidget(buildTestApp());

    await tester.tap(find.text('Practice').last);
    await tester.pumpAndSettle();
    final emptyPracticeState = find.text(
      'Import or save a tab in your Library to start a practice session.',
    );
    // The practice tab lists tabs from the real sqlite database, which
    // resolves on a real async gap that pumpAndSettle alone doesn't wait
    // out; runAsync lets that real Future actually complete.
    await tester.runAsync(() async {
      for (var i = 0; i < 20 && emptyPracticeState.evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    expect(emptyPracticeState, findsOneWidget);
    expect(find.text('Practice'), findsWidgets);

    await tester.restartAndRestore();
    await tester.runAsync(() async {
      for (var i = 0; i < 20 && emptyPracticeState.evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    expect(emptyPracticeState, findsOneWidget);
  });

  testWidgets('keeps pages mounted when switching tabs', (tester) async {
    await tester.pumpWidget(buildTestApp());

    final indexedStack = tester.widget<IndexedStack>(
      find.byType(IndexedStack).first,
    );
    expect(indexedStack.children, hasLength(5));
    expect(find.text('Song or artist', skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(find.text('Import Tab'), findsOneWidget);
    expect(find.text('Song or artist', skipOffstage: false), findsOneWidget);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('all destinations fit a small $platform screen', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
      });

      await tester.pumpWidget(buildTestApp());
      for (final destination in [
        'Practice',
        'Tuner',
        'Library',
        'Settings',
        'Discover',
      ]) {
        await tester.tap(find.text(destination).last);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$destination on $platform',
        );
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
