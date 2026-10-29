import 'package:flutter_test/flutter_test.dart';
import 'package:riffshelf/main.dart';

void main() {
  testWidgets('shows the welcome screen', (tester) async {
    await tester.pumpWidget(const RiffShelfApp());
    expect(find.text('Welcome to RiffShelf'), findsOneWidget);
  });
}
