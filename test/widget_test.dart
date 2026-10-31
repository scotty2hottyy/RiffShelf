import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  testWidgets('shows all navigation destinations and the initial screen', (
    tester,
  ) async {
    await tester.pumpWidget(const RiffShelfApp());

    expect(find.text('Discover'), findsWidgets);
    expect(find.text('Song or artist'), findsOneWidget);
    expect(find.text('Practice'), findsWidgets);
    expect(find.text('Tuner'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('switches tabs and restores the selected tab', (tester) async {
    await tester.pumpWidget(const RiffShelfApp());

    await tester.tap(find.text('Practice').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Choose a tab and start a practice session.'),
      findsOneWidget,
    );
    expect(find.text('Practice'), findsWidgets);

    await tester.restartAndRestore();
    expect(
      find.text('Choose a tab and start a practice session.'),
      findsOneWidget,
    );
  });

  testWidgets('keeps pages mounted when switching tabs', (tester) async {
    await tester.pumpWidget(const RiffShelfApp());

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
}
