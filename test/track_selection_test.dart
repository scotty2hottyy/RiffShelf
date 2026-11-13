import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/features/import/guitar_pro_importer.dart';
import 'package:riffshelf/screens/library_screen.dart';

void main() {
  testWidgets('chooses the requested track', (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await chooseTabTrack(context, const [
                  GuitarProTrackInfo(index: 0, name: 'Guitar', stringCount: 6),
                  GuitarProTrackInfo(index: 1, name: 'Bass', stringCount: 4),
                ]);
              },
              child: const Text('Choose'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bass (4 strings)'));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });
}
