import 'package:flutter_test/flutter_test.dart';
import 'package:soundpola/app.dart';

void main() {
  testWidgets('SoundPola app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SoundpolaApp());
    expect(find.text('捕捉此刻的声音'), findsOneWidget);
  });
}
