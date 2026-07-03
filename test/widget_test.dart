import 'package:flutter_test/flutter_test.dart';

import 'package:drive_shuffle_player/main.dart';

void main() {
  testWidgets('home screen renders library shell', (WidgetTester tester) async {
    await tester.pumpWidget(const DriveShuffleApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Drive Shuffle'), findsOneWidget);
    expect(find.text('\uC804\uCCB4'), findsWidgets);
    expect(find.text('Drive'), findsWidgets);
    expect(find.text('\uC7AC\uC0DD \uBAA9\uB85D'), findsOneWidget);
    expect(find.text('\uCD5C\uADFC'), findsOneWidget);
    expect(find.byTooltip('\uC154\uD50C \uC7AC\uC0DD'), findsOneWidget);
    expect(find.byTooltip('\uC124\uC815'), findsOneWidget);
  });
}
