import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drive_shuffle_player/main.dart';

void main() {
  testWidgets('home screen renders library actions', (WidgetTester tester) async {
    await tester.pumpWidget(const DriveShuffleApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Drive Shuffle'), findsOneWidget);
    expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
    expect(find.text('아직 영상이 없습니다.', skipOffstage: false), findsOneWidget);
  });
}
