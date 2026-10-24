import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/stream_detector_page_web.dart';

void main() {
  testWidgets('web detector accepts authorized direct HLS URLs', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StreamDetectorPage()),
    );

    expect(find.textContaining('Web Stream Tester'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('web-stream-url')),
      'https://cdn.example.com/live/master.m3u8',
    );
    await tester.tap(find.byKey(const Key('web-check-stream')));
    await tester.pump();

    expect(find.textContaining('Ready for testing'), findsOneWidget);
    expect(find.text('Add to Servers'), findsOneWidget);
  });

  testWidgets('web detector rejects a normal website watch page', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StreamDetectorPage()),
    );

    await tester.enterText(
      find.byKey(const Key('web-stream-url')),
      'https://example.com/watch',
    );
    await tester.tap(find.byKey(const Key('web-check-stream')));
    await tester.pump();

    expect(find.textContaining('Enter a direct HTTP(S) media URL'), findsOneWidget);
    expect(find.text('Add to Servers'), findsNothing);
  });
}
