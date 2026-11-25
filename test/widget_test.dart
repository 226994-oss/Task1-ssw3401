import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ssw3401/main.dart';

void main() {
  testWidgets('CameraPage renders initial state', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('GeoPhoto Tag'), findsOneWidget);
    expect(find.text('No photo captured yet'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
  });
}
