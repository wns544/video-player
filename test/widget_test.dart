import 'package:flutter_test/flutter_test.dart';

import 'package:drive_shuffle_player/main.dart';

void main() {
  testWidgets('home screen renders library actions', (WidgetTester tester) async {
    await tester.pumpWidget(const DriveShuffleApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Drive Shuffle'), findsOneWidget);
    expect(find.text('로컬'), findsOneWidget);
    expect(find.text('Drive'), findsOneWidget);
    expect(find.text('플레이어'), findsOneWidget);
  });
}
