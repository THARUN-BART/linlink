import 'package:flutter_test/flutter_test.dart';
import 'package:linlink/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LinLinkApp());
    expect(find.text('Phone ↔ Linux Bridge'), findsOneWidget);
  });
}
