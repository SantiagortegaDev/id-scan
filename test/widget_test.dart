import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const IdScanApp());

    // Verify the app title is shown
    expect(find.text('ID Scan'), findsOneWidget);
  });
}
